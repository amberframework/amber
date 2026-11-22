module Amber::Mica::Deflate
  # Raised when libc's allocator cannot supply the memory an encoder asks
  # for (under 300,000 bytes per stream).
  class OutOfMemoryError < Amber::Mica::Error
  end

  # The encoding engine behind `Amber::Mica::Deflate`, `Amber::Mica::Zlib` and
  # `Amber::Mica::Gzip`, one-shot and streaming.
  #
  # It follows zlib's deflate algorithm (deflate.c) so that compressed
  # sizes track zlib's level for level: a 32 KiB history, hash chains over
  # 3-byte sequences with zlib's hash, zlib's per-level parameters (levels
  # 1 to 3 take the first good match, levels 4 to 9 look one byte ahead
  # for a better one before committing), and a buffer of up to 16,383
  # symbols that `BlockWriter` turns into the smallest of a stored, a
  # fixed-Huffman and a dynamic-Huffman block. Level 0 writes stored
  # blocks. Where Mica differs from zlib: a match may reach the full
  # 32,768 bytes back (zlib stops 262 bytes short).
  #
  # The input is addressed through one pointer:
  #
  # - one-shot: the caller's bytes are searched in place and nothing is
  #   copied;
  # - streaming (and any encode with a preset dictionary): bytes are
  #   copied into a window of `WINDOW_CAPACITY` bytes, and when it fills
  #   the last 32 KiB move to its front.
  #
  # The hash table and the chain table hold stream positions modulo
  # 65,536, as zlib's hold window offsets, so nothing in them changes when
  # the window moves and following a chain is one masked load per
  # candidate. A position more than 32,768 back is out of reach, and one
  # 65,536 back would look near again; so every `CLEAN_PERIOD` positions
  # the hash table's entries that are out of reach are overwritten with a
  # position that stays out of reach until the next cleaning (the work of
  # zlib's `slide_hash`). A chain ends where the next position is not
  # farther back than the last one, which is how an overwritten chain slot
  # shows. Candidates are compared eight bytes at a time.
  #
  # Memory per stream at any level from 1 to 9: the window (65,536 bytes,
  # streaming only), the hash table (65,536), the chain table (65,536) and
  # the symbol buffer (65,536): 262,144 bytes, from libc's allocator
  # rather than the collector's heap, so that an encode per request does
  # not drive collections. `release` frees them (`finish` calls it), and a
  # deflater that is dropped unfinished frees them when it is collected.
  # The output buffer and the code builders are a further 30 KiB or so of
  # collector memory.
  #
  # WARNING: A deflater belongs to one fiber at a time.
  #
  # :nodoc:
  class Deflater
    # The DEFLATE history.
    WINDOW      = 32_768
    WINDOW_MASK = (WINDOW - 1).to_u32
    # The shortest and longest match.
    MIN_MATCH =   3
    MAX_MATCH = 258
    # While at least this many bytes lie ahead, a match can run its full
    # length; the engine waits for more input below it unless it is
    # flushing.
    MIN_LOOKAHEAD = MAX_MATCH + MIN_MATCH + 1
    # zlib's hash: 15 bits over three bytes, each shifted 5 bits further.
    HASH_SIZE = 32_768
    HASH_MASK = (HASH_SIZE - 1).to_u32
    # A block is written when it holds this many symbols (zlib's symbol
    # buffer at its default memory level).
    SYMBOL_LIMIT = 16_383
    # A match of the minimum length this far back costs more than three
    # literals; zlib drops it.
    TOO_FAR = 4_096
    # The streaming window: the history plus the room new input is copied
    # into.
    WINDOW_CAPACITY = 2 * WINDOW
    # The history a slide keeps: one byte more than the window, so the byte
    # 32,768 back stays reachable.
    WINDOW_KEEP = WINDOW + 1
    # Positions encoded between two cleanings of the hash table. With the
    # up to 258 positions one step can add, a kept entry is at most 65,026
    # positions old when it is next looked at, so its distance modulo
    # 65,536 is its distance.
    CLEAN_PERIOD = 32_000
    # A cleaned entry holds the position this far ahead of the cleaning:
    # it reads as more than 32,768 back until the next cleaning.
    STALE_LEAD = 32_767
    # The streaming output buffer. A stored block's bytes bypass it and a
    # compressed block is written through it in pieces, so it never grows.
    STREAM_OUTPUT_BYTES = 16_384

    # Frees a streaming deflater's libc blocks when the collector drops a
    # writer that was never closed. It holds four addresses and no
    # reference, so the collector can finalize it whatever the writer's
    # destination refers to. A finalizer on the writer itself would never
    # run when its destination leads back to it (a response whose output is
    # the writer): the collector does not finalize an object it reaches
    # from itself, and the blocks would stay allocated.
    #
    # :nodoc:
    class ReleaseGuard
      @list_of_blocks = StaticArray(Void*, 4).new(Pointer(Void).null)

      # Records the four blocks the deflater holds now; a null stands for a
      # block it does not hold.
      def hold(tables : Void*, symbols : Void*, previous : Void*, window : Void*) : Nil
        @list_of_blocks[0] = tables
        @list_of_blocks[1] = symbols
        @list_of_blocks[2] = previous
        @list_of_blocks[3] = window
      end

      # Returns true while a recorded block is still to be freed.
      def holds_blocks? : Bool
        @list_of_blocks.any? { |block| !block.null? }
      end

      # Returns nil: the collector calls a finalizer as a C function that
      # returns nothing. A finalizer whose last expression is a large struct
      # (`fill` returns the `StaticArray`) is compiled to take a hidden
      # pointer for that result in the first argument register on x86_64,
      # so the object the collector passes there is taken for it and `self`
      # arrives as null.
      def finalize : Nil
        @list_of_blocks.each { |block| LibC.free(block) unless block.null? }
        @list_of_blocks.fill(Pointer(Void).null)
      end
    end

    # zlib's parameters of one level (its `configuration_table`): stop
    # searching hard once a match is *good_length* long; do not look for a
    # better match past *max_lazy* (levels 1 to 3: the longest match whose
    # inner positions are still hashed); stop at a match of *nice_length*;
    # follow at most *max_chain* candidates.
    record LevelParameters, good_length : Int32, max_lazy : Int32, nice_length : Int32, max_chain : Int32,
      is_lazy : Bool

    LEVELS = StaticArray[
      LevelParameters.new(0, 0, 0, 0, false),
      LevelParameters.new(4, 4, 8, 4, false),
      LevelParameters.new(4, 5, 16, 8, false),
      LevelParameters.new(4, 6, 32, 32, false),
      LevelParameters.new(4, 4, 16, 16, true),
      LevelParameters.new(8, 16, 32, 32, true),
      LevelParameters.new(8, 16, 128, 128, true),
      LevelParameters.new(8, 32, 128, 256, true),
      LevelParameters.new(32, 128, 258, 1_024, true),
      LevelParameters.new(32, 258, 258, 4_096, true),
    ]

    # Raises `ArgumentError` unless *level* is 0 to 9.
    def self.check_level(level : Int32) : Nil
      raise ArgumentError.new("Invalid compression level #{level}: must be 0 to 9") unless 0 <= level <= 9
    end

    # Encodes *input* in one call and returns the stream.
    def self.encode(input : Bytes, format : Format, level : Int32, dictionary : Bytes? = nil,
                    header : Gzip::Header? = nil) : Bytes
      deflater = new(format, level, nil, dictionary, header, input.size)
      begin
        if dictionary
          deflater.write(input)
        else
          deflater.write_in_place(input)
        end
        deflater.finish
      ensure
        deflater.release
      end
      deflater.result
    end

    @format : Format
    @level : Int32
    @parameters : LevelParameters
    @dictionary : Bytes?
    @header : Gzip::Header?
    @blocks : BlockWriter

    # The byte at offset `n` of the input the engine can still see is
    # `@source[n]`. `@slid_bytes` counts how far the window has moved, so
    # offset `n` is stream position `@slid_bytes + n`.
    @source : UInt8* = Pointer(UInt8).null
    @slid_bytes : UInt32 = 0_u32
    @window : UInt8* = Pointer(UInt8).null
    # The offset being encoded, the end of the input seen so far, and the
    # start of the block being collected.
    @position : Int32 = 0
    @fill : Int32 = 0
    @block_start : Int32 = 0
    # False once the window has slid past the start of the block being
    # collected: its bytes cannot be written as a stored block any more.
    @block_bytes_available : Bool = true

    # The block from libc that holds the code builders' workspace, the
    # hash table and a streaming encoder's output buffer.
    @tables : UInt8* = Pointer(UInt8).null
    # For each hash, the position (modulo 65,536) that last had it.
    @head : UInt16* = Pointer(UInt16).null
    # For each position (modulo the window), the position that had the
    # same hash before it.
    @previous : UInt16* = Pointer(UInt16).null
    @positions_until_cleaning : Int32 = CLEAN_PERIOD
    @symbols : UInt32* = Pointer(UInt32).null
    @symbol_count : Int32 = 0

    # The lazy matcher's state between calls: the match found at the
    # previous position and whether that position's byte is still unsent.
    @match_length : Int32 = MIN_MATCH - 1
    @match_distance : UInt32 = 0_u32
    @match_available : Bool = false
    # Positions before `@position` that were too close to the end of the
    # input to hash; they are hashed when more input arrives.
    @unhashed_positions : Int32 = 0

    @checksum : UInt32
    @input_size : UInt32 = 0_u32
    @header_written : Bool = false
    @flushed : Bool = false
    getter? finished : Bool = false

    # *sink* receives the stream as it is produced; without one the output
    # collects for `result`. *expected_input_bytes* sizes the first output
    # buffer and, for a short one-shot input, the tables. *release_guard*
    # frees the blocks of a deflater that is dropped without `release`.
    def initialize(@format : Format, @level : Int32, sink : IO?, @dictionary : Bytes? = nil,
                   @header : Gzip::Header? = nil, expected_input_bytes : Int32 = -1,
                   @release_guard : ReleaseGuard? = nil)
      Deflater.check_level(@level)
      @parameters = LEVELS[@level]
      check_header
      @checksum = @format.zlib? ? 1_u32 : 0_u32
      symbol_bytes = 0
      chain_bytes = 0
      hash_bytes = 0
      if @level > 0
        chain_entries = WINDOW
        symbol_entries = SYMBOL_LIMIT + 1
        if expected_input_bytes >= 0 && @dictionary.nil?
          chain_entries = Math.min(chain_entries, expected_input_bytes + 1)
          symbol_entries = Math.min(symbol_entries, expected_input_bytes + 1)
        end
        symbol_bytes = symbol_entries * 4
        chain_bytes = chain_entries * 2
        hash_bytes = HASH_SIZE * 2
      end
      # Three blocks come from libc, each small enough for the allocator
      # to hand back a block it has just been given back, which costs a
      # short-lived encoder far less than one large block of fresh pages:
      # the code builders' workspace with the hash table and, with a
      # sink, the output buffer, which then never grows; the symbol
      # buffer; and the chain table. Without a sink the output is the
      # result and belongs to the collector. The workspace and the hash
      # table start zeroed: a hash entry of 0 names stream position 0,
      # which nothing matches.
      workspace_bytes = BlockWriter::WORKSPACE_BYTES
      output_bytes = sink ? STREAM_OUTPUT_BYTES + BlockWriter::SLACK : 0
      @tables = allocate(workspace_bytes + hash_bytes + output_bytes)
      @tables.clear(workspace_bytes + hash_bytes)
      @head = (@tables + workspace_bytes).as(UInt16*)
      @symbols = allocate(symbol_bytes).as(UInt32*) if symbol_bytes > 0
      @previous = allocate(chain_bytes).as(UInt16*) if chain_bytes > 0
      buffer = if sink
                 Bytes.new(@tables + workspace_bytes + hash_bytes, output_bytes)
               else
                 BlockWriter.buffer_for(Math.max(expected_input_bytes // 2, 0) + 1_024)
               end
      @blocks = BlockWriter.new(sink, buffer, @tables)
      record_blocks_in_release_guard
      load_dictionary
    end

    # Frees the tables and the window. The deflater encodes nothing after
    # this; `result` stays readable. `finish` calls it; whoever builds a
    # deflater and may drop it unfinished calls it too (`Deflater.encode`
    # in an `ensure`) or hands it a `ReleaseGuard` (`StreamWriter`), which
    # keeps the one-shot path free of a finalizer per call.
    def release : Nil
      LibC.free(@tables.as(Void*)) unless @tables.null?
      LibC.free(@symbols.as(Void*)) unless @symbols.null?
      LibC.free(@previous.as(Void*)) unless @previous.null?
      LibC.free(@window.as(Void*)) unless @window.null?
      @tables = Pointer(UInt8).null
      @symbols = Pointer(UInt32).null
      @previous = Pointer(UInt16).null
      @window = Pointer(UInt8).null
      record_blocks_in_release_guard
    end

    # Bytes the engine holds for the window, the hash and chain tables and
    # the symbol buffer of a stream of any length.
    def table_bytes : Int32
      bytes = @window.null? ? 0 : WINDOW_CAPACITY
      bytes += HASH_SIZE * 2 + WINDOW * 2 + (SYMBOL_LIMIT + 1) * 4 if @level > 0
      bytes
    end

    # Bytes the engine holds for its output buffer.
    def output_buffer_bytes : Int32
      @blocks.buffer_bytes
    end

    # Bytes the engine holds for the Huffman code builders.
    def workspace_bytes : Int32
      BlockWriter::WORKSPACE_BYTES
    end

    # Encodes the whole of *input* where it lies. The engine reads *input*
    # until `finish` returns; this is the one-shot path and takes the place
    # of every `write`.
    def write_in_place(input : Bytes) : Nil
      write_header
      add_to_checksum(input)
      @source = input.to_unsafe
      @fill = input.size
    end

    # Copies *input* into the window and encodes what can be encoded
    # without knowing what follows.
    def write(input : Bytes) : Nil
      return if input.empty?
      raise IO::Error.new("The stream is finished") if @finished
      write_header
      add_to_checksum(input)
      window = window_for_writing
      offset = 0
      while offset < input.size
        slide_window if @fill == WINDOW_CAPACITY
        count = Math.min(WINDOW_CAPACITY - @fill, input.size - offset)
        (window + @fill).copy_from(input.to_unsafe + offset, count)
        @fill += count
        offset += count
        hash_the_unhashed_positions
        compress(false)
      end
      @flushed = false
    end

    # Ends the current block and appends an empty stored block, so that
    # everything written so far can be decoded and the output ends on a
    # byte boundary (zlib's Z_SYNC_FLUSH). With *is_full* the history is
    # dropped too: the bytes that follow refer to nothing before this
    # point (Z_FULL_FLUSH). A flush right after a flush writes nothing.
    def flush(is_full : Bool = false) : Nil
      return if @finished
      unless @flushed
        write_header
        compress(true)
        write_block(false) if @symbol_count > 0 || (@level == 0 && @fill > @block_start)
        @blocks.write_sync_marker
        @flushed = true
      end
      drop_history if is_full
      @blocks.drain
    end

    # Writes the final block and the trailer and frees the tables. The
    # stream is complete.
    def finish : Nil
      return if @finished
      write_header
      compress(true)
      write_block(true)
      write_trailer
      @blocks.drain
      @finished = true
      release
    end

    # The whole stream, for a deflater without a sink.
    def result : Bytes
      @blocks.result
    end

    # ---- Containers ----------------------------------------------------

    private def check_header : Nil
      header = @header
      return unless header
      extra_field = header.extra_field
      if extra_field && extra_field.size > 65_535
        raise ArgumentError.new("A gzip extra field holds at most 65,535 bytes (got #{extra_field.size})")
      end
      check_no_zero_byte("file name", header.file_name)
      check_no_zero_byte("comment", header.comment)
    end

    private def check_no_zero_byte(field : String, bytes : Bytes?) : Nil
      return unless bytes
      raise ArgumentError.new("A gzip #{field} cannot contain a zero byte") if bytes.includes?(0_u8)
    end

    private def write_header : Nil
      return if @header_written
      @header_written = true
      if @format.zlib?
        write_zlib_header
      elsif @format.gzip?
        write_gzip_header
      end
    end

    # RFC 1950: CMF (method 8, a 32 KiB window), then FLG with the level
    # hint zlib writes, FDICT and the check bits; then the dictionary's
    # Adler-32 when there is one.
    private def write_zlib_header : Nil
      level_hint = if @level < 2
                     0_u32
                   elsif @level < 6
                     1_u32
                   elsif @level == 6
                     2_u32
                   else
                     3_u32
                   end
      header = (0x78_u32 << 8) | (level_hint << 6)
      dictionary = @dictionary
      header |= 0x20 if dictionary
      header += 31 - header % 31
      @blocks.write_byte((header >> 8).to_u8!)
      @blocks.write_byte(header.to_u8!)
      @blocks.write_u32_be(Adler32.update(1_u32, dictionary)) if dictionary
    end

    # RFC 1952: the fixed ten bytes, then FEXTRA, FNAME and FCOMMENT when
    # the header has them. Without a header the modification time is 0 and
    # the operating system 255 (unknown), so the same input always gives
    # the same bytes; XFL then says 2 for level 9 and 4 for levels 0 and 1,
    # as zlib does.
    private def write_gzip_header : Nil
      header = @header
      flags = 0_u8
      modification_time = 0_u32
      extra_flags = @level == 9 ? 2_u8 : (@level < 2 ? 4_u8 : 0_u8)
      operating_system = 255_u8
      if header
        flags |= 0x01 if header.is_text
        flags |= 0x04 if header.extra_field
        flags |= 0x08 if header.file_name
        flags |= 0x10 if header.comment
        modification_time = header.modification_time
        extra_flags = header.extra_flags
        operating_system = header.operating_system
      end
      @blocks.write_byte(Inflater::MAGIC[0])
      @blocks.write_byte(Inflater::MAGIC[1])
      @blocks.write_byte(8_u8)
      @blocks.write_byte(flags)
      @blocks.write_u32_le(modification_time)
      @blocks.write_byte(extra_flags)
      @blocks.write_byte(operating_system)
      return unless header
      if extra_field = header.extra_field
        @blocks.write_u16_le(extra_field.size.to_u32)
        @blocks.write_bytes(extra_field)
      end
      if file_name = header.file_name
        @blocks.write_bytes(file_name)
        @blocks.write_byte(0_u8)
      end
      if comment = header.comment
        @blocks.write_bytes(comment)
        @blocks.write_byte(0_u8)
      end
    end

    private def write_trailer : Nil
      if @format.zlib?
        @blocks.write_u32_be(@checksum)
      elsif @format.gzip?
        @blocks.write_u32_le(@checksum)
        @blocks.write_u32_le(@input_size)
      end
    end

    private def add_to_checksum(input : Bytes) : Nil
      if @format.zlib?
        @checksum = Adler32.update(@checksum, input)
      elsif @format.gzip?
        @checksum = CRC32.update(@checksum, input)
      end
      @input_size &+= input.size.to_u32!
    end

    # ---- Memory, the window and slides ---------------------------------

    private def allocate(bytes : Int32) : UInt8*
      pointer = LibC.malloc(bytes.to_u64).as(UInt8*)
      raise OutOfMemoryError.new("Cannot allocate #{bytes} bytes for the Deflate encoder") if pointer.null?
      pointer
    end

    private def window_for_writing : UInt8*
      return @window unless @window.null?
      @window = allocate(WINDOW_CAPACITY)
      @source = @window
      record_blocks_in_release_guard
      @window
    end

    private def record_blocks_in_release_guard : Nil
      release_guard = @release_guard
      return unless release_guard
      release_guard.hold(@tables.as(Void*), @symbols.as(Void*), @previous.as(Void*), @window.as(Void*))
    end

    # Puts the last 32 KiB of the preset dictionary in front of the input
    # and hashes it, so the first bytes can refer to it.
    private def load_dictionary : Nil
      dictionary = @dictionary
      return unless dictionary
      return if @level == 0 || dictionary.empty?
      tail = dictionary.size > WINDOW ? dictionary[dictionary.size - WINDOW, WINDOW] : dictionary
      window_for_writing.copy_from(tail.to_unsafe, tail.size)
      @fill = tail.size
      @position = tail.size
      @block_start = tail.size
      @unhashed_positions = tail.size
      hash_the_unhashed_positions
      clean_the_hash_table
    end

    # Moves the history to the front of the window to make room. Offsets
    # drop by the amount moved and `@slid_bytes` grows by it, so stream
    # positions (what the tables hold) stay as they are.
    private def slide_window : Nil
      history = @level == 0 ? 0 : WINDOW_KEEP
      shift = @position - history
      return if shift <= 0
      @window.move_from(@window + shift, @fill - shift)
      @fill -= shift
      @position -= shift
      @block_bytes_available = false if @block_start < shift
      @block_start -= shift
      @slid_bytes &+= shift.to_u32!
    end

    # Fills the hash table with a position no match can reach before the
    # first cleaning: the table is empty.
    private def mark_every_hash_stale : Nil
      stale = ((@slid_bytes &+ @position.to_u32!) &+ STALE_LEAD).to_u16!
      head = @head
      index = 0
      while index < HASH_SIZE
        head[index] = stale
        index &+= 1
      end
      @positions_until_cleaning = CLEAN_PERIOD
    end

    # Overwrites every hash table entry that is more than 32,768 positions
    # back (or exactly 65,536) with a position that stays out of reach
    # until the next cleaning.
    private def clean_the_hash_table : Nil
      now = (@slid_bytes &+ @position.to_u32!).to_u16!
      stale = now &+ STALE_LEAD.to_u16
      head = @head
      index = 0
      while index < HASH_SIZE
        entry = head[index]
        head[index] = (now &- entry) &- 1_u16 < WINDOW.to_u16 ? entry : stale
        index &+= 1
      end
      @positions_until_cleaning = CLEAN_PERIOD
    end

    # Forgets everything before the current position (a full flush): no
    # match may reach back past it.
    private def drop_history : Nil
      return if @level == 0
      @unhashed_positions = 0
      unless @window.null?
        # Everything is encoded, so the window restarts empty.
        @position = 0
        @fill = 0
        @block_start = 0
        @block_bytes_available = true
        @slid_bytes = 0_u32
      end
      mark_every_hash_stale
    end

    # ---- Blocks --------------------------------------------------------

    private def write_block(is_final : Bool) : Nil
      if @level == 0
        @blocks.write_stored(@source + @block_start, @fill - @block_start, is_final)
        @position = @fill
      else
        stored = @block_bytes_available ? @source + @block_start : Pointer(UInt8).null
        @blocks.write_block(@symbols, @symbol_count, stored, @position - @block_start, @block_bytes_available, is_final)
        @symbol_count = 0
      end
      @block_start = @position
      @block_bytes_available = true
    end

    # ---- Matching ------------------------------------------------------

    # Encodes from `@position` on. Unless *is_flushing*, it stops while
    # `MIN_LOOKAHEAD` bytes remain so that no match is cut short by input
    # that has not arrived.
    private def compress(is_flushing : Bool) : Nil
      if @level == 0
        store_whole_blocks
        return
      end
      loop do
        if @parameters.is_lazy
          compress_lazily(is_flushing)
        else
          compress_greedily(is_flushing)
        end
        # The loops also stop when a cleaning is due; clean and go on.
        break if @positions_until_cleaning > 0
        clean_the_hash_table
      end
    end

    # Level 0: writes each full 65,535 bytes as a stored block; the rest
    # waits for `write_block`.
    private def store_whole_blocks : Nil
      while @fill - @block_start >= BlockWriter::MAX_STORED_BYTES
        @blocks.write_stored(@source + @block_start, BlockWriter::MAX_STORED_BYTES, false)
        @block_start += BlockWriter::MAX_STORED_BYTES
      end
      @position = @block_start
    end

    @[AlwaysInline]
    private def load_u64(pointer : UInt8*) : UInt64
      value = uninitialized UInt64
      pointerof(value).as(UInt8*).copy_from(pointer, 8)
      {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::LittleEndian %}
        value = value.byte_swap
      {% end %}
      value
    end

    @[AlwaysInline]
    private def load_u16(pointer : UInt8*) : UInt16
      value = uninitialized UInt16
      pointerof(value).as(UInt8*).copy_from(pointer, 2)
      value
    end

    # zlib's hash of the three bytes at *pointer*.
    @[AlwaysInline]
    private def hash_at(pointer : UInt8*) : UInt32
      ((pointer[0].to_u32 << 10) ^ (pointer[1].to_u32 << 5) ^ pointer[2].to_u32) & HASH_MASK
    end

    # Records *position* under the hash of its three bytes and returns the
    # position (modulo 65,536) that had that hash before.
    @[AlwaysInline]
    private def insert_position(source : UInt8*, head : UInt16*, previous : UInt16*, position : Int32) : UInt32
      hash = hash_at(source + position)
      earlier = head[hash]
      head[hash] = position.to_u16!
      previous[position.to_u32! & WINDOW_MASK] = earlier
      earlier.to_u32
    end

    # Returns how many of the first *limit* bytes at *first* and *second*
    # are equal, comparing eight bytes at a time.
    @[AlwaysInline]
    private def common_length(first : UInt8*, second : UInt8*, limit : Int32) : Int32
      length = 0
      while length &+ 8 <= limit
        difference = load_u64(first + length) ^ load_u64(second + length)
        if difference != 0
          return length &+ (difference.trailing_zeros_count >> 3)
        end
        length &+= 8
      end
      while length < limit && first[length] == second[length]
        length &+= 1
      end
      length
    end

    # Walks the hash chain (zlib's `longest_match`) from the candidate
    # *earlier*, which lies *distance* back from *position*, and returns
    # the longest match longer than *best_length* with its distance, or
    # *best_length* and 0. A candidate is compared in full only when its
    # two bytes at the current best length match, since only then can it
    # be longer. The chain ends at a position that is not farther back
    # than the last one or is past *max_distance*.
    @[AlwaysInline]
    private def longest_match(scan : UInt8*, previous : UInt16*, position : UInt32, earlier : UInt32, distance : UInt32,
                              max_distance : UInt32, best_length : Int32, nice_length : Int32, chain : Int32,
                              max_length : Int32) : {Int32, UInt32}
      best_distance = 0_u32
      return {best_length, best_distance} if best_length >= max_length
      scan_end = load_u16(scan + (best_length &- 1))
      loop do
        candidate = scan - distance
        if load_u16(candidate + (best_length &- 1)) == scan_end
          length = common_length(scan, candidate, max_length)
          if length > best_length
            best_length = length
            best_distance = distance
            break if length >= nice_length
            scan_end = load_u16(scan + (best_length &- 1))
          end
        end
        earlier = previous[earlier & WINDOW_MASK].to_u32
        next_distance = (position &- earlier) & 0xFFFF_u32
        break unless next_distance &- distance &- 1 < max_distance &- distance
        distance = next_distance
        chain &-= 1
        break if chain == 0
      end
      {best_length, best_distance}
    end

    # Levels 1 to 3 (zlib's `deflate_fast`): take the longest match at each
    # position, or a literal.
    private def compress_greedily(is_flushing : Bool) : Nil
      # Inside the loop a position is its stream position modulo 65,536
      # plus the offset, so the tables take its low 16 bits as they are.
      first_position = (@slid_bytes & 0xFFFF).to_i32!
      source = @source - first_position
      head = @head
      previous = @previous
      symbols = @symbols
      literal_frequencies = @blocks.literal_frequencies
      distance_frequencies = @blocks.distance_frequencies
      length_symbols = BlockWriter::LENGTH_SYMBOLS.to_unsafe
      distance_symbols = BlockWriter::DISTANCE_SYMBOLS.to_unsafe
      position = @position &+ first_position
      fill = @fill &+ first_position
      cleaning_position = position &+ @positions_until_cleaning
      started_at = position
      symbol_count = @symbol_count
      nice_length = @parameters.nice_length
      max_chain = @parameters.max_chain
      max_insert = @parameters.max_lazy

      while position < cleaning_position
        lookahead = fill &- position
        if lookahead < MIN_LOOKAHEAD
          break if !is_flushing || lookahead == 0
        end
        length = MIN_MATCH - 1
        match_distance = 0_u32
        if lookahead >= MIN_MATCH
          earlier = insert_position(source, head, previous, position)
          distance = (position.to_u32! &- earlier) & 0xFFFF_u32
          max_distance = Math.min(Math.max(position &- first_position &- 1, 0), WINDOW).to_u32!
          if distance &- 1 < max_distance
            length, match_distance = longest_match(source + position, previous, position.to_u32!, earlier, distance,
              max_distance, MIN_MATCH - 1, Math.min(nice_length, lookahead), max_chain, Math.min(MAX_MATCH, lookahead))
          end
        end

        if length >= MIN_MATCH
          symbols[symbol_count] = (match_distance << 8) | (length &- MIN_MATCH).to_u32!
          symbol_count &+= 1
          literal_frequencies[257 &+ length_symbols[length &- MIN_MATCH]] &+= 1
          code = match_distance &- 1
          distance_frequencies[code < 256 ? distance_symbols[code] : distance_symbols[256_u32 &+ (code >> 7)]] &+= 1
          match_end = position &+ length
          if length <= max_insert && fill &- match_end >= MIN_MATCH
            position &+= 1
            while position < match_end
              insert_position(source, head, previous, position)
              position &+= 1
            end
          else
            position = match_end
          end
        else
          byte = source[position]
          symbols[symbol_count] = byte.to_u32
          symbol_count &+= 1
          literal_frequencies[byte] &+= 1
          position &+= 1
        end

        if symbol_count == SYMBOL_LIMIT
          @position = position &- first_position
          @symbol_count = symbol_count
          write_block(false)
          symbol_count = 0
        end
      end

      @position = position &- first_position
      @symbol_count = symbol_count
      @positions_until_cleaning -= position &- started_at
      @unhashed_positions = Math.min(@position, MIN_MATCH - 1) if is_flushing && position == fill
    end

    # Levels 4 to 9 (zlib's `deflate_slow`): a match found at one position
    # is sent only if the next position has none longer; otherwise the
    # byte goes out as a literal and the longer match takes over.
    private def compress_lazily(is_flushing : Bool) : Nil
      first_position = (@slid_bytes & 0xFFFF).to_i32!
      source = @source - first_position
      head = @head
      previous = @previous
      symbols = @symbols
      literal_frequencies = @blocks.literal_frequencies
      distance_frequencies = @blocks.distance_frequencies
      length_symbols = BlockWriter::LENGTH_SYMBOLS.to_unsafe
      distance_symbols = BlockWriter::DISTANCE_SYMBOLS.to_unsafe
      position = @position &+ first_position
      fill = @fill &+ first_position
      cleaning_position = position &+ @positions_until_cleaning
      started_at = position
      symbol_count = @symbol_count
      good_length = @parameters.good_length
      max_lazy = @parameters.max_lazy
      nice_length = @parameters.nice_length
      max_chain = @parameters.max_chain
      match_length = @match_length
      match_distance = @match_distance
      is_byte_pending = @match_available

      while position < cleaning_position
        lookahead = fill &- position
        if lookahead < MIN_LOOKAHEAD
          break if !is_flushing || lookahead == 0
        end
        previous_length = match_length
        previous_distance = match_distance
        match_length = MIN_MATCH - 1
        if lookahead >= MIN_MATCH
          earlier = insert_position(source, head, previous, position)
          distance = (position.to_u32! &- earlier) & 0xFFFF_u32
          max_distance = Math.min(Math.max(position &- first_position &- 1, 0), WINDOW).to_u32!
          if previous_length < max_lazy && distance &- 1 < max_distance
            chain = previous_length >= good_length ? max_chain >> 2 : max_chain
            match_length, found_distance = longest_match(source + position, previous, position.to_u32!, earlier, distance,
              max_distance, previous_length, Math.min(nice_length, lookahead), chain, Math.min(MAX_MATCH, lookahead))
            if match_length > previous_length
              match_distance = found_distance
              match_length = MIN_MATCH - 1 if match_length == MIN_MATCH && match_distance > TOO_FAR
            end
          end
        end

        if previous_length >= MIN_MATCH && match_length <= previous_length
          # The match found at the previous position stands.
          symbols[symbol_count] = (previous_distance << 8) | (previous_length &- MIN_MATCH).to_u32!
          symbol_count &+= 1
          literal_frequencies[257 &+ length_symbols[previous_length &- MIN_MATCH]] &+= 1
          code = previous_distance &- 1
          distance_frequencies[code < 256 ? distance_symbols[code] : distance_symbols[256_u32 &+ (code >> 7)]] &+= 1
          match_end = position &+ previous_length &- 1
          last_hashable = fill &- MIN_MATCH
          position &+= 1
          while position < match_end
            insert_position(source, head, previous, position) if position <= last_hashable
            position &+= 1
          end
          is_byte_pending = false
          match_length = MIN_MATCH - 1
          if symbol_count == SYMBOL_LIMIT
            @position = position &- first_position
            @symbol_count = symbol_count
            write_block(false)
            symbol_count = 0
          end
        elsif is_byte_pending
          byte = source[position &- 1]
          symbols[symbol_count] = byte.to_u32
          symbol_count &+= 1
          literal_frequencies[byte] &+= 1
          if symbol_count == SYMBOL_LIMIT
            @position = position &- first_position
            @symbol_count = symbol_count
            write_block(false)
            symbol_count = 0
          end
          position &+= 1
        else
          is_byte_pending = true
          position &+= 1
        end
      end

      if is_flushing && position == fill
        if is_byte_pending
          byte = source[position &- 1]
          symbols[symbol_count] = byte.to_u32
          symbol_count &+= 1
          literal_frequencies[byte] &+= 1
          is_byte_pending = false
        end
        match_length = MIN_MATCH - 1
        @unhashed_positions = Math.min(position &- first_position, MIN_MATCH - 1)
      end
      @position = position &- first_position
      @symbol_count = symbol_count
      @positions_until_cleaning -= position &- started_at
      @match_length = match_length
      @match_distance = match_distance
      @match_available = is_byte_pending
    end

    # Hashes the positions a flush or the dictionary left unhashed, now
    # that the bytes after them are known.
    private def hash_the_unhashed_positions : Nil
      return if @level == 0
      while @unhashed_positions > 0 && @position - @unhashed_positions + MIN_MATCH <= @fill
        first_position = (@slid_bytes & 0xFFFF).to_i32!
        insert_position(@source - first_position, @head, @previous, first_position + @position - @unhashed_positions)
        @unhashed_positions -= 1
      end
    end
  end
end
