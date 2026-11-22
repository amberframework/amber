module Amber::Mica::Core
  # Buffered input for a format's scanner, included into the scanner class so
  # the hot loops read the buffer through instance variables with no extra
  # indirection.
  #
  # The input is either a `Bytes` read in place or a stream (`IO`, possibly
  # a `Transcoder`) read into one growable buffer. The scanner keeps
  # everything from `@mark` (the start of the current token) and from
  # `@pin` (when set) in the buffer; `fill` compacts the bytes before them
  # and doubles the buffer only when one token needs it, up to the token
  # limit. Offsets held across a `fill` must therefore be relative to
  # `@mark`.
  #
  # Positions: `@base_offset + @pos` is the offset of the current byte in
  # the bytes the scanner sees; `source_offset_at` maps it to an offset in
  # the original input (here: plus any skipped prefix such as a byte order
  # mark; `TextInput` adds transcoded input).
  #
  # This module is byte-oriented and knows nothing about characters, so
  # binary formats (CBOR) include it alone. Text formats include
  # `TextInput` (which includes this module) and `LineTracking`. The
  # including type implements the hooks below.
  module ByteInput
    # Initial size of the stream buffer.
    INITIAL_BUFFER_SIZE = 64 * 1024

    # Bytes beyond the token limit the buffer may hold for markup around a
    # token (delimiters, names, quotes).
    TOKEN_SLACK = 64 * 1024

    @buffer : Bytes = Bytes.empty
    @pos = 0
    @limit = 0
    @mark = 0
    @pin = -1
    @io : IO? = nil
    @io_eof = true
    @base_offset = 0_i64
    @input_bytes = 0_i64
    @input_bytes_moved = 0_i64
    @source_prefix_bytes = 0_i64

    # Returns the largest token, in bytes, the buffer must hold.
    private abstract def input_token_limit : Int32

    # Returns the cap on decoded input bytes, or nil.
    private abstract def input_size_limit : Int64?

    # Raises the format's positioned limit error.
    private abstract def input_limit_error(message : String) : NoReturn

    # Called with the bytes compaction or growth is about to copy, before
    # copying, so the format can charge (and stop) the move.
    private abstract def moving_input(count : Int64) : Nil

    # Called before the bytes `@buffer[0, keep]` are discarded.
    private abstract def discarding_input(keep : Int32) : Nil

    # Called after *count* more decoded bytes arrived (for work accounting).
    private abstract def input_received(count : Int32) : Nil

    # Reads *bytes* in place; *prefix_bytes* source bytes (a byte order mark)
    # precede them in the original input.
    private def setup_in_memory(bytes : Bytes, prefix_bytes : Int32 = 0) : Nil
      @buffer = bytes
      @pos = 0
      @limit = bytes.size
      @io = nil
      @io_eof = true
      @source_prefix_bytes = prefix_bytes.to_i64
      @input_bytes = bytes.size.to_i64
      input_received(bytes.size)
      check_initial_input_size
    end

    # Reads from *io*, starting with the already-read source bytes in
    # *carried*.
    private def setup_stream(io : IO, carried : Bytes = Bytes.empty, prefix_bytes : Int32 = 0) : Nil
      @io = io
      @io_eof = false
      @pos = 0
      @limit = carried.size
      @source_prefix_bytes = prefix_bytes.to_i64
      @input_bytes = carried.size.to_i64
      # The carried bytes are input: credited first, then their copy into
      # the buffer is charged before it runs.
      input_received(carried.size)
      moving_input(carried.size.to_i64) unless carried.empty?
      @buffer = Bytes.new(Math.max(INITIAL_BUFFER_SIZE, carried.size))
      carried.copy_to(@buffer)
      check_initial_input_size
    end

    # Makes at least one more byte available. Returns false at the end of
    # the source. Keeps every byte from `@mark` (and from `@pin` when set),
    # so offsets relative to the mark stay valid.
    private def fill : Bool
      io = @io
      return false if io.nil? || @io_eof
      keep = @mark
      pin = @pin
      keep = pin if pin >= 0 && pin < keep
      if keep > 0
        discarding_input(keep)
        count = @limit - keep
        moving_input(count.to_i64)
        @input_bytes_moved += count
        # Overlapping ranges inside one buffer: move (memmove) through
        # bounds-checked subslices.
        @buffer[0, count].move_from(@buffer[keep, count]) if count > 0
        @base_offset += keep
        @pos -= keep
        @limit -= keep
        @mark -= keep
        @pin -= keep if pin >= 0
      end
      if @limit == @buffer.size
        # Capped at the largest buffer an Int32 index can address, so a
        # raised token limit never overflows the size computation.
        capacity = Math.min(input_token_limit.to_i64 + TOKEN_SLACK, Int32::MAX.to_i64)
        if @buffer.size.to_i64 >= capacity
          input_limit_error("Token exceeds the token size limit (#{input_token_limit} bytes)")
        end
        # Double, but never past the token limit plus its slack.
        moving_input(@limit.to_i64)
        grown = Bytes.new(Math.min(@buffer.size.to_i64 * 2, capacity).to_i32)
        grown.copy_from(@buffer[0, @limit])
        @input_bytes_moved += @limit
        @buffer = grown
      end
      read = io.read(@buffer[@limit, read_space])
      if read == 0
        @io_eof = true
        return false
      end
      @limit += read
      @input_bytes += read
      input_received(read)
      check_input_size
      true
    end

    # Returns how many bytes the next read may fill: the free buffer space,
    # or at most one byte past the input size limit (enough to detect that
    # it was exceeded). Never overflows, even for a limit of Int64::MAX.
    private def read_space : Int32
      space = @buffer.size - @limit
      max = input_size_limit || return space
      remaining = max - @input_bytes
      remaining < space ? Math.max(remaining + 1, 1_i64).to_i32 : space
    end

    # Checks the bytes a source starts with.
    private def check_initial_input_size : Nil
      check_input_size
    end

    # Raises once more than the input size limit has arrived. The bytes past
    # the limit are the last ones received, so the first of them is at
    # buffer index `@limit - (@input_bytes - max)`.
    private def check_input_size : Nil
      max = input_size_limit || return
      return unless @input_bytes > max
      excess_index = (@limit - (@input_bytes - max)).clamp(@pos.to_i64, @limit.to_i64).to_i32
      input_size_exceeded("Input exceeds the input size limit (#{max} bytes)", excess_index)
    end

    # Raises the format's positioned input size error. *excess_index* is
    # the buffer index of the first byte past the limit; the error points
    # there.
    private abstract def input_size_exceeded(message : String, excess_index : Int32) : NoReturn

    # Makes *count* bytes available from the current position. Returns
    # false when the source ends first.
    @[AlwaysInline]
    private def ensure_bytes(count : Int32) : Bool
      while @limit - @pos < count
        return false unless fill
      end
      true
    end

    # Returns true when the current source has no more bytes.
    @[AlwaysInline]
    private def at_source_end? : Bool
      @pos >= @limit && !fill
    end

    # Returns the byte at the current position, or -1 at the end.
    @[AlwaysInline]
    private def peek_byte : Int32
      return -1 if @pos >= @limit && !fill
      @buffer[@pos].to_i32
    end

    # Returns the byte *offset* bytes ahead, or -1 past the end.
    @[AlwaysInline]
    private def peek_byte_at(offset : Int32) : Int32
      return -1 unless ensure_bytes(offset + 1)
      @buffer[@pos + offset].to_i32
    end

    # Returns true when the input at the current position starts with
    # *literal*. Consumes nothing.
    private def starts_with?(literal : String) : Bool
      size = literal.bytesize
      return false unless ensure_bytes(size)
      @buffer[@pos, size] == literal.to_slice
    end

    # Consumes *literal* when the input starts with it.
    private def skip_literal?(literal : String) : Bool
      return false unless starts_with?(literal)
      @pos += literal.bytesize
      true
    end

    # Returns the offset in the original input of byte *pos* of *buffer*,
    # whose first byte is at offset *base*.
    private def source_offset_at(buffer : Bytes, pos : Int32, base : Int64) : Int64
      @source_prefix_bytes + base + pos
    end

    # Same; an untranscoded offset maps without scanning, so the step block
    # is never called.
    private def source_offset_at(buffer : Bytes, pos : Int32, base : Int64, & : Int32 ->) : Int64
      @source_prefix_bytes + base + pos
    end

    # :nodoc:
    #
    # Returns the bytes copied while compacting or growing the buffer. Each
    # token's bytes are copied O(1) times amortized, so this stays linear in
    # the input; specs assert it.
    def input_bytes_moved : Int64
      @input_bytes_moved
    end
  end
end
