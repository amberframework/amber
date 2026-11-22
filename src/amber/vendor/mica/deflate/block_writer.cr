module Amber::Mica::Deflate
  # Writes DEFLATE blocks (RFC 1951) for the encoder: it owns the output
  # buffer, the bit buffer and the three Huffman code builders, and turns a
  # buffer of literal and match symbols into whichever block is smallest,
  # stored, fixed Huffman or dynamic Huffman, by zlib's rule
  # (`_tr_flush_block` of trees.c).
  #
  # Bits collect in a 64-bit buffer and leave it in whole bytes. Before a
  # block is written its exact size is known, so the buffer is given that
  # much room once and the symbol loop writes without checking.
  #
  # Output goes to *sink* whenever the buffer needs room and at every
  # `drain`; without a sink the buffer grows and `result` returns it.
  #
  # :nodoc:
  class BlockWriter
    # Alphabet sizes (RFC 1951, section 3.2.5 and 3.2.7).
    LITERAL_CODES     = 286
    DISTANCE_CODES    =  30
    CODE_LENGTH_CODES =  19
    END_OF_BLOCK      = 256

    # Code-length symbols: repeat the previous length 3 to 6 times, repeat
    # zero 3 to 10 times, repeat zero 11 to 138 times.
    REPEAT_PREVIOUS = 16
    REPEAT_ZERO     = 17
    REPEAT_ZERO_FAR = 18

    # The most bytes one stored block holds.
    MAX_STORED_BYTES = 65_535

    # Bytes kept free past every reservation, so a 64-bit store of the bit
    # buffer never passes the end.
    SLACK = 16

    # Extra bits of length symbols 257 to 285 and of distance symbols.
    LENGTH_EXTRA   = HuffmanTable::LENGTH_EXTRA
    DISTANCE_EXTRA = HuffmanTable::DISTANCE_EXTRA
    # Extra bits of the code-length symbols.
    CODE_LENGTH_EXTRA = StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 2_u8, 3_u8, 7_u8]

    # The length symbol (0 to 28, for 257 to 285) of each match length
    # minus 3.
    LENGTH_SYMBOLS = begin
      symbols = StaticArray(UInt8, 256).new(0_u8)
      length = 0
      28.times do |symbol|
        (1 << LENGTH_EXTRA[symbol]).times do
          symbols[length] = symbol.to_u8
          length += 1
        end
      end
      # Length 258 has its own symbol with no extra bits.
      symbols[255] = 28_u8
      symbols
    end

    # The first match length minus 3 of each length symbol.
    LENGTH_BASES = begin
      bases = StaticArray(UInt8, 29).new(0_u8)
      29.times { |symbol| bases[symbol] = (HuffmanTable::LENGTH_BASES[symbol] - 3).to_u8 }
      bases
    end

    # The distance symbol of each distance minus 1: entries 0 to 255
    # directly, larger values through entry `256 + (value >> 7)`.
    DISTANCE_SYMBOLS = begin
      symbols = StaticArray(UInt8, 512).new(0_u8)
      30.times do |symbol|
        first = HuffmanTable::DISTANCE_BASES[symbol].to_i32 - 1
        last = first + (1 << DISTANCE_EXTRA[symbol]) - 1
        (first..last).each do |value|
          if value < 256
            symbols[value] = symbol.to_u8
          elsif value & 0x7F == 0
            symbols[256 + (value >> 7)] = symbol.to_u8
          end
        end
      end
      symbols
    end

    # The first distance minus 1 of each distance symbol.
    DISTANCE_BASES = begin
      bases = StaticArray(UInt16, 30).new(0_u16)
      30.times { |symbol| bases[symbol] = HuffmanTable::DISTANCE_BASES[symbol] - 1 }
      bases
    end

    # Code lengths of the fixed literal/length code (RFC 1951, section
    # 3.2.6), with the two symbols that never occur.
    FIXED_LITERAL_LENGTHS = begin
      lengths = StaticArray(UInt8, 288).new(8_u8)
      (144..255).each { |symbol| lengths[symbol] = 9_u8 }
      (256..279).each { |symbol| lengths[symbol] = 7_u8 }
      lengths
    end

    # Code lengths of the fixed distance code.
    FIXED_DISTANCE_LENGTHS = StaticArray(UInt8, 30).new(5_u8)

    # The symbol tables of the fixed codes, built once.
    FIXED_TABLES = begin
      literal_codes = StaticArray(UInt16, 288).new(0_u16)
      distance_codes = StaticArray(UInt16, 30).new(0_u16)
      HuffmanCodeBuilder.assign_canonical_codes(FIXED_LITERAL_LENGTHS.to_unsafe, literal_codes.to_unsafe, 288)
      HuffmanCodeBuilder.assign_canonical_codes(FIXED_DISTANCE_LENGTHS.to_unsafe, distance_codes.to_unsafe, 30)
      tables = SymbolTables.new
      tables.fill(FIXED_LITERAL_LENGTHS.to_unsafe, literal_codes.to_unsafe, 288, FIXED_DISTANCE_LENGTHS.to_unsafe,
        distance_codes.to_unsafe, DISTANCE_CODES)
      tables
    end

    # What the symbol loop reads for one block: for each literal byte and
    # each match length the bits to write (the code, then a length's extra
    # bits) with their count in bits 24 to 31; for each distance symbol the
    # code in bits 0 to 14, its length in bits 16 to 19 and the count of
    # extra bits in bits 24 to 27.
    #
    # :nodoc:
    struct SymbolTables
      # Entries 0 to 255 are literals, 256 to 511 match lengths minus 3.
      @literal_and_length = uninitialized StaticArray(UInt32, 512)
      @distance = uninitialized StaticArray(UInt32, 30)
      @end_of_block = 0_u32

      def literal_and_length : UInt32*
        @literal_and_length.to_unsafe
      end

      def distance : UInt32*
        @distance.to_unsafe
      end

      # The end-of-block code with its length in bits 24 to 31.
      def end_of_block : UInt32
        @end_of_block
      end

      # Fills the entries of the first *literal_count* literal and length
      # symbols and the first *distance_count* distance symbols, which
      # are the ones the block uses.
      def fill(literal_lengths : UInt8*, literal_codes : UInt16*, literal_count : Int32, distance_lengths : UInt8*,
               distance_codes : UInt16*, distance_count : Int32) : Nil
        table = @literal_and_length.to_unsafe
        literal_end = Math.min(literal_count, 256)
        symbol = 0
        while symbol < literal_end
          table[symbol] = literal_codes[symbol].to_u32 | (literal_lengths[symbol].to_u32 << 24)
          symbol += 1
        end
        @end_of_block = literal_codes[END_OF_BLOCK].to_u32 | (literal_lengths[END_OF_BLOCK].to_u32 << 24)
        length_symbols = LENGTH_SYMBOLS.to_unsafe
        length_bases = LENGTH_BASES.to_unsafe
        length_extra = LENGTH_EXTRA.to_unsafe
        length = 0
        while length < 256
          length_symbol = length_symbols[length].to_i32
          symbol = 257 + length_symbol
          break if symbol >= literal_count
          code_bits = literal_lengths[symbol].to_u32
          extra = (length - length_bases[length_symbol].to_i32).to_u32!
          table[256 + length] = literal_codes[symbol].to_u32 | (extra << code_bits) |
                                ((code_bits + length_extra[length_symbol]) << 24)
          length += 1
        end
        distance_extra = DISTANCE_EXTRA.to_unsafe
        distance = @distance.to_unsafe
        symbol = 0
        while symbol < distance_count
          distance[symbol] = distance_codes[symbol].to_u32 | (distance_lengths[symbol].to_u32 << 16) |
                             (distance_extra[symbol].to_u32 << 24)
          symbol += 1
        end
      end
    end

    @sink : IO?
    @buffer : Bytes
    @position : Int32 = 0
    @bit_buffer : UInt64 = 0_u64
    @bit_count : Int32 = 0
    @literal : HuffmanCodeBuilder
    @distance : HuffmanCodeBuilder
    @code_length : HuffmanCodeBuilder
    @tables : SymbolTables

    # Bytes handed to the sink so far.
    getter drained_bytes : Int64 = 0_i64

    # Returns an output buffer from the collector with room for *capacity*
    # bytes and the slack.
    def self.buffer_for(capacity : Int32) : Bytes
      Bytes.new(GC.malloc_atomic(capacity + SLACK).as(UInt8*), capacity + SLACK)
    end

    # Bytes of workspace the three code builders share.
    WORKSPACE_BYTES = HuffmanCodeBuilder.storage_bytes(LITERAL_CODES) + HuffmanCodeBuilder.storage_bytes(DISTANCE_CODES) +
                      HuffmanCodeBuilder.storage_bytes(CODE_LENGTH_CODES)

    # *buffer* is the first output buffer. A writer with a sink drains it
    # and never needs another; a writer without one replaces it with a
    # larger buffer from the collector when a block needs more room.
    # *workspace* is `WORKSPACE_BYTES` of zeroed memory aligned to 4 bytes
    # that outlives every block written.
    def initialize(@sink : IO?, @buffer : Bytes, workspace : UInt8*)
      @literal = HuffmanCodeBuilder.new(LITERAL_CODES, 15, LENGTH_EXTRA.to_slice, 257, FIXED_LITERAL_LENGTHS.to_slice,
        workspace)
      workspace += HuffmanCodeBuilder.storage_bytes(LITERAL_CODES)
      @distance = HuffmanCodeBuilder.new(DISTANCE_CODES, 15, DISTANCE_EXTRA.to_slice, 0, FIXED_DISTANCE_LENGTHS.to_slice,
        workspace)
      workspace += HuffmanCodeBuilder.storage_bytes(DISTANCE_CODES)
      @code_length = HuffmanCodeBuilder.new(CODE_LENGTH_CODES, 7, CODE_LENGTH_EXTRA.to_slice, 0, nil, workspace)
      @tables = SymbolTables.new
      start_block
    end

    # Counters of the literal bytes (0 to 255), the end of block (256) and
    # the length symbols (257 to 285) of the block being collected.
    def literal_frequencies : Int32*
      @literal.frequencies
    end

    # Counters of the distance symbols of the block being collected.
    def distance_frequencies : Int32*
      @distance.frequencies
    end

    # Writes whole bytes (a header or a trailer). The bit buffer is empty
    # at those points.
    def write_bytes(bytes : Bytes) : Nil
      reserve(bytes.size)
      (@buffer.to_unsafe + @position).copy_from(bytes.to_unsafe, bytes.size)
      @position += bytes.size
    end

    def write_byte(byte : UInt8) : Nil
      reserve(1)
      @buffer.to_unsafe[@position] = byte
      @position += 1
    end

    def write_u16_le(value : UInt32) : Nil
      write_byte(value.to_u8!)
      write_byte((value >> 8).to_u8!)
    end

    def write_u32_le(value : UInt32) : Nil
      write_u16_le(value & 0xFFFF)
      write_u16_le(value >> 16)
    end

    def write_u32_be(value : UInt32) : Nil
      write_u32_le(value.byte_swap)
    end

    # Writes the block that holds *symbol_count* symbols of *symbols* (a
    # literal byte, or a match as its length minus 3 in bits 0 to 7 and its
    # distance in bits 8 to 23), whose frequencies are already counted. The
    # block's *stored_bytes* input bytes start at *stored*; when
    # *is_stored_available* is false they are no longer in memory and the
    # block cannot be stored.
    def write_block(symbols : UInt32*, symbol_count : Int32, stored : UInt8*, stored_bytes : Int32,
                    is_stored_available : Bool, is_final : Bool) : Nil
      @literal.build
      @distance.build
      last_code_length_index = build_code_length_code
      dynamic_bits = @literal.optimal_bits + @distance.optimal_bits + @code_length.optimal_bits +
                     3 * (last_code_length_index + 1) + 5 + 5 + 4
      fixed_bits = @literal.static_bits + @distance.static_bits
      dynamic_bytes = (dynamic_bits + 3 + 7) >> 3
      fixed_bytes = (fixed_bits + 3 + 7) >> 3
      smallest_bytes = Math.min(dynamic_bytes, fixed_bytes)
      stored_chunks = stored_bytes <= MAX_STORED_BYTES ? 1 : (stored_bytes + MAX_STORED_BYTES - 1) // MAX_STORED_BYTES

      if is_stored_available && stored_bytes + 4 + 5 * (stored_chunks - 1) <= smallest_bytes
        write_stored(stored, stored_bytes, is_final)
      elsif fixed_bytes == smallest_bytes
        reserve(@sink ? 1 : fixed_bytes + 1)
        put_bits((1_u32 << 1) | (is_final ? 1_u32 : 0_u32), 3)
        tables = FIXED_TABLES
        write_symbols(symbols, symbol_count, pointerof(tables))
      else
        reserve(@sink ? MAX_DYNAMIC_HEADER_BYTES : dynamic_bytes + 1)
        put_bits((2_u32 << 1) | (is_final ? 1_u32 : 0_u32), 3)
        write_code_lengths(last_code_length_index)
        @tables.fill(@literal.lengths, @literal.codes, @literal.max_code + 1, @distance.lengths, @distance.codes,
          @distance.max_code + 1)
        write_symbols(symbols, symbol_count, pointerof(@tables))
      end
      start_block
      finish_last_byte if is_final
    end

    # Writes *count* bytes at *bytes* as stored blocks of at most 65,535
    # bytes (one empty block when *count* is 0); the last one is marked
    # final when *is_final* is set.
    def write_stored(bytes : UInt8*, count : Int32, is_final : Bool) : Nil
      sink = @sink
      offset = 0
      loop do
        size = Math.min(count - offset, MAX_STORED_BYTES)
        is_last = offset + size == count
        reserve(5)
        put_bits(is_final && is_last ? 1_u32 : 0_u32, 3)
        finish_last_byte
        output = @buffer.to_unsafe + @position
        output[0] = size.to_u8!
        output[1] = (size >> 8).to_u8!
        output[2] = (~size).to_u8!
        output[3] = (~size >> 8).to_u8!
        @position += 4
        if sink && size > 0
          # The bytes go to the sink as they are, after the block's header.
          drain
          sink.write(Bytes.new(bytes + offset, size, read_only: true))
          @drained_bytes += size
        else
          reserve(size)
          (@buffer.to_unsafe + @position).copy_from(bytes + offset, size)
          @position += size
        end
        offset += size
        break if is_last
      end
    end

    # Writes an empty stored block, which ends on a byte boundary: what a
    # sync flush appends so that a decoder can decode everything before it.
    def write_sync_marker : Nil
      write_stored(Pointer(UInt8).null, 0, false)
    end

    # Hands every whole byte written so far to the sink.
    def drain : Nil
      sink = @sink
      return unless sink
      return if @position == 0
      sink.write(@buffer[0, @position])
      @drained_bytes += @position
      @position = 0
    end

    # The bytes written so far, for a writer without a sink. The slice
    # shares the output buffer unless less than half of it is used.
    def result : Bytes
      return @buffer[0, @position] if @position * 2 >= @buffer.size
      exact = Bytes.new(GC.malloc_atomic(@position).as(UInt8*), @position)
      exact.copy_from(@buffer.to_unsafe, @position)
      exact
    end

    # Bytes this writer holds for its output buffer.
    def buffer_bytes : Int32
      @buffer.size
    end

    # Clears the counters for the next block. The end-of-block symbol
    # occurs once in every block.
    private def start_block : Nil
      @literal.reset
      @distance.reset
      @code_length.reset
      @literal.frequencies[END_OF_BLOCK] = 1
    end

    # Makes room for *count* more bytes plus the slack: drains to the sink
    # first, and grows the buffer when that is not enough.
    private def reserve(count : Int32) : Nil
      needed = count + SLACK
      return if @buffer.size - @position >= needed
      drain
      return if @buffer.size - @position >= needed
      capacity = Math.max(@buffer.size.to_i64 * 2, @position.to_i64 + needed)
      raise ArgumentError.new("The compressed output passes 2 GiB") if @position.to_i64 + needed > Int32::MAX
      capacity = Math.min(capacity, Int32::MAX.to_i64).to_i32
      grown = Bytes.new(GC.malloc_atomic(capacity).as(UInt8*), capacity)
      grown.copy_from(@buffer.to_unsafe, @position)
      @buffer = grown
    end

    # Appends the low *count* bits of *value* (at most 32) and writes out
    # the whole bytes. The caller has reserved the room.
    @[AlwaysInline]
    private def put_bits(value : UInt32, count : Int32) : Nil
      bits = @bit_buffer | (value.to_u64 << @bit_count)
      bit_count = @bit_count + count
      output = @buffer.to_unsafe + @position
      store_u64(output, bits)
      @position += bit_count >> 3
      @bit_buffer = bits >> (bit_count & ~7)
      @bit_count = bit_count & 7
    end

    # Pads the last partial byte with zero bits and writes it.
    private def finish_last_byte : Nil
      return if @bit_count == 0
      @buffer.to_unsafe[@position] = @bit_buffer.to_u8!
      @position += 1
      @bit_buffer = 0_u64
      @bit_count = 0
    end

    @[AlwaysInline]
    private def store_u64(pointer : UInt8*, value : UInt64) : Nil
      {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::LittleEndian %}
        value = value.byte_swap
      {% end %}
      pointer.copy_from(pointerof(value).as(UInt8*), 8)
    end

    # More than a dynamic block's header takes: 14 bits of counts, 19
    # 3-bit lengths and at most 316 code-length symbols of 14 bits.
    MAX_DYNAMIC_HEADER_BYTES = 1_024

    # Symbols written between two reservations when the output goes to a
    # sink, so the output buffer stays small whatever a block's size.
    SYMBOLS_PER_RESERVATION = 2_048
    # The most bytes one symbol takes: a 15-bit length code with 5 extra
    # bits and a 15-bit distance code with 13.
    MAX_SYMBOL_BYTES = 6

    # Writes the symbols and the end of block. Without a sink the caller
    # has reserved the block's exact size; with one, room is reserved (and
    # the buffer drained) every `SYMBOLS_PER_RESERVATION` symbols.
    private def write_symbols(symbols : UInt32*, symbol_count : Int32, tables : SymbolTables*) : Nil
      if @sink
        offset = 0
        while offset < symbol_count
          count = Math.min(symbol_count - offset, SYMBOLS_PER_RESERVATION)
          reserve(count * MAX_SYMBOL_BYTES)
          write_run_of_symbols(symbols + offset, count, tables)
          offset += count
        end
        reserve(MAX_SYMBOL_BYTES)
      else
        write_run_of_symbols(symbols, symbol_count, tables)
      end
      put_bits(tables.value.end_of_block & 0xFFFFFF, (tables.value.end_of_block >> 24).to_i32)
    end

    # The symbol loop: every symbol adds at most 48 bits to the at most 7
    # left in the bit buffer, then the whole bytes are stored with one
    # 64-bit write.
    private def write_run_of_symbols(symbols : UInt32*, symbol_count : Int32, tables : SymbolTables*) : Nil
      literal_and_length = tables.value.literal_and_length
      distance_table = tables.value.distance
      distance_symbols = DISTANCE_SYMBOLS.to_unsafe
      distance_bases = DISTANCE_BASES.to_unsafe
      output = @buffer.to_unsafe + @position
      bits = @bit_buffer
      bit_count = @bit_count
      index = 0
      while index < symbol_count
        symbol = symbols[index]
        index &+= 1
        distance = symbol >> 8
        if distance == 0
          entry = literal_and_length[symbol]
          bits |= (entry & 0xFFFFFF).to_u64.unsafe_shl(bit_count)
          bit_count &+= (entry >> 24).to_i32!
        else
          entry = literal_and_length[256_u32 &+ (symbol & 0xFF)]
          bits |= (entry & 0xFFFFFF).to_u64.unsafe_shl(bit_count)
          bit_count &+= (entry >> 24).to_i32!
          distance &-= 1
          distance_symbol = distance < 256 ? distance_symbols[distance] : distance_symbols[256_u32 &+ (distance >> 7)]
          entry = distance_table[distance_symbol]
          bits |= (entry & 0x7FFF).to_u64.unsafe_shl(bit_count)
          bit_count &+= ((entry >> 16) & 0xF).to_i32!
          bits |= (distance &- distance_bases[distance_symbol]).to_u64.unsafe_shl(bit_count)
          bit_count &+= (entry >> 24).to_i32!
        end
        store_u64(output, bits)
        output += bit_count >> 3
        bits = bits.unsafe_shr(bit_count & ~7)
        bit_count &= 7
      end
      @bit_buffer = bits
      @bit_count = bit_count
      @position = (output - @buffer.to_unsafe).to_i32
    end

    # Counts the code-length symbols the two codes' lengths run-length
    # encode to, builds the code-length code and returns the index of the
    # last code-length length that must be sent (zlib's `build_bl_tree`).
    private def build_code_length_code : Int32
      count_code_length_symbols(@literal.lengths, @literal.max_code)
      count_code_length_symbols(@distance.lengths, @distance.max_code)
      @code_length.build
      lengths = @code_length.lengths
      index = CODE_LENGTH_CODES - 1
      while index >= 3
        break if lengths[Inflater::CODE_LENGTH_ORDER[index]] != 0
        index -= 1
      end
      index
    end

    # Walks one code's lengths as runs (zlib's `scan_tree` and
    # `send_tree`): a run of 3 or more equal lengths becomes repeat
    # symbols. Yields each code-length symbol with its repeat count.
    private def each_code_length_symbol(lengths : UInt8*, max_code : Int32, & : Int32, Int32 ->) : Nil
      previous_length = -1
      next_length = lengths[0].to_i32
      count = 0
      max_count = next_length == 0 ? 138 : 7
      min_count = next_length == 0 ? 3 : 4
      symbol = 0
      while symbol <= max_code
        length = next_length
        next_length = symbol == max_code ? -1 : lengths[symbol + 1].to_i32
        symbol += 1
        count += 1
        next if count < max_count && length == next_length
        if count < min_count
          count.times { yield length, 0 }
        elsif length != 0
          if length != previous_length
            yield length, 0
            count -= 1
          end
          yield REPEAT_PREVIOUS, count - 3
        elsif count <= 10
          yield REPEAT_ZERO, count - 3
        else
          yield REPEAT_ZERO_FAR, count - 11
        end
        count = 0
        previous_length = length
        if next_length == 0
          max_count = 138
          min_count = 3
        elsif length == next_length
          max_count = 6
          min_count = 3
        else
          max_count = 7
          min_count = 4
        end
      end
    end

    private def count_code_length_symbols(lengths : UInt8*, max_code : Int32) : Nil
      frequencies = @code_length.frequencies
      each_code_length_symbol(lengths, max_code) { |symbol, _| frequencies[symbol] += 1 }
    end

    # Writes a dynamic block's header after its three type bits: the three
    # counts, the code-length code's lengths and the two codes' lengths.
    private def write_code_lengths(last_code_length_index : Int32) : Nil
      put_bits((@literal.max_code + 1 - 257).to_u32, 5)
      put_bits(@distance.max_code.to_u32, 5)
      put_bits((last_code_length_index + 1 - 4).to_u32, 4)
      lengths = @code_length.lengths
      (0..last_code_length_index).each do |index|
        put_bits(lengths[Inflater::CODE_LENGTH_ORDER[index]].to_u32, 3)
      end
      write_code_length_symbols(@literal.lengths, @literal.max_code)
      write_code_length_symbols(@distance.lengths, @distance.max_code)
    end

    private def write_code_length_symbols(lengths : UInt8*, max_code : Int32) : Nil
      codes = @code_length.codes
      code_lengths = @code_length.lengths
      each_code_length_symbol(lengths, max_code) do |symbol, repeat|
        put_bits(codes[symbol].to_u32, code_lengths[symbol].to_i32)
        if symbol == REPEAT_PREVIOUS
          put_bits(repeat.to_u32, 2)
        elsif symbol == REPEAT_ZERO
          put_bits(repeat.to_u32, 3)
        elsif symbol == REPEAT_ZERO_FAR
          put_bits(repeat.to_u32, 7)
        end
      end
    end
  end
end
