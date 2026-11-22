module Amber::Mica::Deflate
  # Builds the lookup tables the inflater decodes Huffman codes with
  # (canonical codes, RFC 1951 section 3.2.2), in the two-level layout zlib
  # and libdeflate use: a root table indexed by the next `root` bits of the
  # input (codes are stored bit-reversed, as DEFLATE sends them), and for
  # codes longer than `root` bits a subtable sized to fit them.
  #
  # Each entry is a `UInt32`:
  #
  # | Bits  | Meaning |
  # |-------|---------|
  # | 0-7   | code bits this entry consumes |
  # | 8-11  | code bits (lengths, distances: bits 0-7 then hold code plus extra bits) or subtable index bits |
  # | 13    | `SUBTABLE`: bits 16-31 hold the subtable's start |
  # | 14    | `END_OF_BLOCK` |
  # | 15    | `EXCEPTIONAL`: end of block, subtable or invalid code |
  # | 16-30 | literal byte, length or distance base, code-length symbol |
  # | 31    | `LITERAL` |
  #
  # An entry with `EXCEPTIONAL` and neither `SUBTABLE` nor `END_OF_BLOCK`
  # marks a bit pattern no code uses (an incomplete code, or symbols 286,
  # 287, 30 and 31 of the fixed codes) and fails the decode.
  #
  # :nodoc:
  module HuffmanTable
    LITERAL      = 0x8000_0000_u32
    EXCEPTIONAL  = 0x0000_8000_u32
    END_OF_BLOCK = 0x0000_4000_u32
    SUBTABLE     = 0x0000_2000_u32
    # A bit pattern no code uses. It takes one bit, as zlib's unused
    # entries do: they occur only in an empty code or a one-code code of
    # length 1, so a decoder judges the pattern on that one bit.
    INVALID = EXCEPTIONAL | 1_u32

    # Root bits per alphabet.
    LITERAL_LENGTH_ROOT = 10
    DISTANCE_ROOT       =  8
    CODE_LENGTH_ROOT    =  7

    # Entries each table may need, root plus subtables, rounded up from
    # zlib's `enough` bounds (1,332 for 286 symbols with a 10-bit root, 402
    # for 30 symbols with an 8-bit root). The builder checks the bound
    # anyway.
    LITERAL_LENGTH_ENTRIES = 2_048
    DISTANCE_ENTRIES       = 1_024
    CODE_LENGTH_ENTRIES    =   128

    # Base length and extra bits of length symbols 257 to 285.
    LENGTH_BASES = StaticArray[3_u16, 4_u16, 5_u16, 6_u16, 7_u16, 8_u16, 9_u16, 10_u16, 11_u16, 13_u16, 15_u16, 17_u16,
      19_u16, 23_u16, 27_u16, 31_u16, 35_u16, 43_u16, 51_u16, 59_u16, 67_u16, 83_u16, 99_u16, 115_u16,
      131_u16, 163_u16, 195_u16, 227_u16, 258_u16]
    LENGTH_EXTRA = StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 1_u8, 1_u8, 2_u8, 2_u8, 2_u8,
      2_u8, 3_u8, 3_u8, 3_u8, 3_u8, 4_u8, 4_u8, 4_u8, 4_u8, 5_u8, 5_u8, 5_u8, 5_u8, 0_u8]
    # Base distance and extra bits of distance symbols 0 to 29.
    DISTANCE_BASES = StaticArray[1_u16, 2_u16, 3_u16, 4_u16, 5_u16, 7_u16, 9_u16, 13_u16, 17_u16, 25_u16, 33_u16, 49_u16,
      65_u16, 97_u16, 129_u16, 193_u16, 257_u16, 385_u16, 513_u16, 769_u16, 1025_u16, 1537_u16, 2049_u16,
      3073_u16, 4097_u16, 6145_u16, 8193_u16, 12289_u16, 16385_u16, 24577_u16]
    DISTANCE_EXTRA = StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 2_u8, 2_u8, 3_u8, 3_u8, 4_u8, 4_u8, 5_u8, 5_u8, 6_u8,
      6_u8, 7_u8, 7_u8, 8_u8, 8_u8, 9_u8, 9_u8, 10_u8, 10_u8, 11_u8, 11_u8, 12_u8, 12_u8, 13_u8, 13_u8]

    # Which alphabet a table decodes; it decides each symbol's entry and
    # whether an incomplete code is allowed.
    enum Alphabet
      CodeLength
      LiteralLength
      Distance
    end

    # Why a set of code lengths does not form a usable code.
    enum Problem
      None
      Oversubscribed
      Incomplete
    end

    # What `build` returns: the problem, if any; the work the build is
    # charged (the entries a full *root*-bit table holds, so the charge
    # does not depend on how small a table the code needed); and the bits
    # that index the root table, at most *root* (a code whose longest
    # codeword is shorter gets a smaller table).
    record Built, problem : Problem, work : Int32, table_bits : Int32

    # Every symbol's entry without its code length: `entry_for` computed
    # once, so a build adds the length to a table lookup.
    LITERAL_LENGTH_RESULTS = begin
      results = Slice(UInt32).new(288, 0_u32)
      288.times { |symbol| results[symbol] = result_for(Alphabet::LiteralLength, symbol) }
      results
    end

    # :ditto:
    DISTANCE_RESULTS = begin
      results = Slice(UInt32).new(32, 0_u32)
      32.times { |symbol| results[symbol] = result_for(Alphabet::Distance, symbol) }
      results
    end

    # :ditto:
    CODE_LENGTH_RESULTS = begin
      results = Slice(UInt32).new(19, 0_u32)
      19.times { |symbol| results[symbol] = result_for(Alphabet::CodeLength, symbol) }
      results
    end

    # Fills *table* (with room for *capacity* entries) for the code whose
    # lengths are `lengths[0, count]` (each at most 15), with a root table
    # of at most *root* bits.
    #
    # Follows zlib's acceptance rules: an oversubscribed code is always
    # rejected; an incomplete code is accepted only for the literal/length
    # and distance alphabets and only when it is a single code of length 1;
    # a code with no symbols at all is accepted and every bit pattern of it
    # decodes as invalid.
    #
    # The root table is filled the way libdeflate fills it: codewords are
    # visited in canonical order, each writes one entry at its bits
    # reversed, and whenever the code length grows the filled part of the
    # table is doubled by copying it, so a build costs one pass over the
    # symbols plus one copy of the table.
    def self.build(table : UInt32*, capacity : Int32, lengths : UInt8*, count : Int32, root : Int32,
                   alphabet : Alphabet) : Built
      # Two sets of counters, for even and odd symbols: consecutive
      # symbols often share a length, and two increments of one counter in
      # a row would wait on each other.
      counts_storage = uninitialized StaticArray(Int32, 32)
      counts = counts_storage.to_unsafe
      32.times { |length| counts[length] = 0 }
      odd_counts = counts + 16
      symbol = 0
      while symbol &+ 1 < count
        counts[lengths[symbol]] &+= 1
        odd_counts[lengths[symbol &+ 1]] &+= 1
        symbol &+= 2
      end
      counts[lengths[symbol]] &+= 1 if symbol < count
      16.times { |length| counts[length] &+= odd_counts[length] }
      max_length = 15
      while max_length > 0 && counts[max_length] == 0
        max_length -= 1
      end
      root_size = 1 << root
      if max_length == 0
        table[0] = INVALID
        return Built.new(Problem::None, root_size, 0)
      end

      # Where each length's symbols start in the sorted list, and the code
      # space the code uses in units of the longest codeword.
      offsets_storage = uninitialized StaticArray(Int32, 16)
      offsets = offsets_storage.to_unsafe
      used = 0
      position = 0
      length = 1
      while length <= max_length
        offsets[length] = position
        position &+= counts[length]
        used = (used << 1) &+ counts[length]
        length &+= 1
      end
      full = 1 << max_length
      return Built.new(Problem::Oversubscribed, 0, 0) if used > full
      results = case alphabet
                in .code_length?    then CODE_LENGTH_RESULTS.to_unsafe
                in .literal_length? then LITERAL_LENGTH_RESULTS.to_unsafe
                in .distance?       then DISTANCE_RESULTS.to_unsafe
                end
      if used < full
        return Built.new(Problem::Incomplete, 0, 0) if alphabet.code_length? || max_length != 1
        # A single code of length 1: bit 0 decodes it and bit 1 is invalid.
        symbol = 0
        while lengths[symbol] != 1
          symbol &+= 1
        end
        table[0] = results[symbol] &+ 0x101_u32
        table[1] = INVALID
        return Built.new(Problem::None, root_size &+ (root_size >> 1), 1)
      end

      sorted_storage = uninitialized StaticArray(UInt16, 320)
      sorted = sorted_storage.to_unsafe
      symbol = 0
      while symbol < count
        length = lengths[symbol].to_i32
        if length != 0
          sorted[offsets[length]] = symbol.to_u16!
          offsets[length] &+= 1
        end
        symbol &+= 1
      end

      # Codewords no longer than the root table: one entry each, at the
      # codeword's bits reversed (DEFLATE sends a code's first bit first);
      # the filled part doubles as the length grows.
      table_bits = max_length < root ? max_length : root
      code = 0_u32
      length = 1
      while length <= table_bits
        added = (length.to_u32! << 8) &+ length.to_u32!
        shift = 32 &- length
        stop = sorted + counts[length]
        while sorted < stop
          table[code.bit_reverse.unsafe_shr(shift)] = results[sorted.value] &+ added
          sorted += 1
          code &+= 1
        end
        code <<= 1
        (table + (1 << length)).copy_from(table, 1 << length) if length < table_bits
        length &+= 1
      end
      return Built.new(Problem::None, root_size, table_bits) if max_length <= root

      # Longer codewords: a subtable per root prefix, sized to hold every
      # codeword that starts with it.
      table_end = 1 << table_bits
      root_mask = (table_end &- 1).to_u32!
      work = root_size
      prefix = UInt32::MAX
      subtable_start = 0
      while length <= max_length
        remaining = counts[length]
        code_bits = (length &- table_bits).to_u32!
        added = (code_bits << 8) &+ code_bits
        shift = 32 &- length
        stride = 1 << code_bits
        while remaining > 0
          reversed = code.bit_reverse.unsafe_shr(shift)
          if reversed & root_mask != prefix
            prefix = reversed & root_mask
            subtable_start = table_end
            subtable_bits = code_bits.to_i32!
            space = remaining
            while space < (1 << subtable_bits)
              subtable_bits &+= 1
              space = (space << 1) &+ counts[table_bits &+ subtable_bits]
            end
            table_end = subtable_start &+ (1 << subtable_bits)
            raise Amber::Mica::Error.new("internal error: Huffman table overflow") if table_end > capacity
            table[prefix] = EXCEPTIONAL | SUBTABLE | (subtable_start.to_u32! << 16) | (subtable_bits.to_u32! << 8) |
                            table_bits.to_u32!
            work = work &- 1 &+ (1 << subtable_bits)
          end
          entry = results[sorted.value] &+ added
          sorted += 1
          index = subtable_start &+ (reversed >> table_bits).to_i32!
          loop do
            table[index] = entry
            index &+= stride
            break unless index < table_end
          end
          code &+= 1
          remaining &-= 1
        end
        code <<= 1
        length &+= 1
      end
      Built.new(Problem::None, work, table_bits)
    end

    # Returns the entry for *symbol* without its code length (see `build`).
    private def self.result_for(alphabet : Alphabet, symbol : Int32) : UInt32
      case alphabet
      in .code_length?
        symbol.to_u32 << 16
      in .literal_length?
        if symbol < 256
          LITERAL | (symbol.to_u32 << 16)
        elsif symbol == 256
          EXCEPTIONAL | END_OF_BLOCK
        elsif symbol <= 285
          index = symbol - 257
          (LENGTH_BASES[index].to_u32 << 16) | LENGTH_EXTRA[index].to_u32
        else
          EXCEPTIONAL
        end
      in .distance?
        if symbol < 30
          (DISTANCE_BASES[symbol].to_u32 << 16) | DISTANCE_EXTRA[symbol].to_u32
        else
          EXCEPTIONAL
        end
      end
    end

    # The fixed literal/length table (RFC 1951, section 3.2.6): symbols 0
    # to 143 have 8 bits, 144 to 255 have 9, 256 to 279 have 7 and 280 to
    # 287 have 8. Symbols 286 and 287 decode as invalid.
    FIXED_LITERAL_LENGTH = begin
      lengths = StaticArray(UInt8, 288).new(0_u8)
      288.times do |symbol|
        lengths[symbol] = symbol < 144 ? 8_u8 : symbol < 256 ? 9_u8 : symbol < 280 ? 7_u8 : 8_u8
      end
      table = Slice(UInt32).new(LITERAL_LENGTH_ENTRIES, INVALID)
      build(table.to_unsafe, table.size, lengths.to_unsafe, 288, LITERAL_LENGTH_ROOT, Alphabet::LiteralLength)
      table
    end
    # The bits that index `FIXED_LITERAL_LENGTH` (its longest codeword).
    FIXED_LITERAL_LENGTH_BITS = 9

    # The fixed distance table: 32 codes of 5 bits; 30 and 31 decode as
    # invalid.
    FIXED_DISTANCE = begin
      lengths = StaticArray(UInt8, 32).new(5_u8)
      table = Slice(UInt32).new(DISTANCE_ENTRIES, INVALID)
      build(table.to_unsafe, table.size, lengths.to_unsafe, 32, DISTANCE_ROOT, Alphabet::Distance)
      table
    end
    # The bits that index `FIXED_DISTANCE`.
    FIXED_DISTANCE_BITS = 5
  end
end
