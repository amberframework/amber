module Amber::Mica::Core
  # Read-only IO that turns UTF-16, UTF-32 or ISO-8859-1 from *source* into
  # UTF-8, in Crystal (no iconv).
  #
  # Invalid input is never repaired or dropped. It becomes a marker byte that
  # is never valid UTF-8, so the format's scanner stops at the exact place
  # and reports it:
  #
  # - `INVALID_UNIT` (0xFF) stands for one whole bad code unit: an unpaired
  #   UTF-16 surrogate, or a UTF-32 value that is a surrogate or above
  #   U+10FFFF.
  # - `TRUNCATED_BYTE` (0xFE) stands for one byte of an incomplete final code
  #   unit (one per leftover byte).
  #
  # `source_size` maps decoded bytes back to source bytes, which is how
  # `ByteInput` reports error offsets in the original input.
  class Transcoder < IO
    INVALID_UNIT   = 0xFF_u8
    TRUNCATED_BYTE = 0xFE_u8

    # Returns the encoding of the source bytes.
    getter source_encoding : Encoding

    # Called after every read from the source returns, so the owner can
    # check its deadline between the several reads one output fill may
    # need. `TextInput` sets it.
    property after_source_read : Proc(Nil)? = nil

    @input : Bytes
    @input_start = 0
    @input_end = 0
    @pending_high = -1
    @eof = false

    # *prefix* holds source bytes already read from *source* (for example
    # while sniffing a byte order mark); they are decoded first. The
    # constructor copies *prefix* unmetered: a caller with a meter charges
    # a long prefix before constructing (`TextInput#switch_to_transcoder`
    # does); the XML reader's sniffed prefix is at most four bytes.
    def initialize(@source : IO, @source_encoding : Encoding, prefix : Bytes = Bytes.empty)
      unless @source_encoding.transcoded?
        raise ArgumentError.new("Transcoder does not handle #{@source_encoding.label}")
      end
      @input = Bytes.new(Math.max(16 * 1024, prefix.size + 4))
      prefix.copy_to(@input)
      @input_end = prefix.size
    end

    # Returns the number of source bytes the decoded UTF-8 *decoded* came
    # from. *decoded* must start on a sequence boundary of this transcoder's
    # output.
    def self.source_size(encoding : Encoding, decoded : Bytes) : Int64
      total = 0_i64
      decoded.each do |byte|
        next if byte & 0xC0 == 0x80 && byte < 0xC0 # continuation byte
        total += if byte == TRUNCATED_BYTE
                   1
                 elsif encoding.iso8859_1?
                   1
                 elsif encoding.utf32?
                   4
                 elsif byte >= 0xF0 && byte <= 0xF4
                   4 # supplementary character: a surrogate pair
                 else
                   2 # BMP character or one invalid unit
                 end
      end
      total
    end

    # Fills *slice* with UTF-8. Returns 0 at the end of the source. Needs
    # room for one encoded code point (4 bytes); smaller slices get the
    # bytes one read at a time through an internal carry. Each call reads
    # from the source at most once for every code unit it needs to
    # complete (at most four reads), then returns what it has decoded.
    def read(slice : Bytes) : Int32
      return read_small(slice) if slice.size < 4
      written = 0
      refilled = false
      while written + 4 <= slice.size
        unit_size = unit_bytes
        if @input_end - @input_start < unit_size
          # Return what is decoded rather than wait on the source again, so
          # the caller regains control (and checks its deadline) after at
          # most one round of source reads per call.
          break if refilled && written > 0
          refill(unit_size)
          refilled = true
          if @input_end - @input_start < unit_size
            written = finish(slice, written)
            break
          end
        end
        written = decode_unit(read_unit, slice, written)
      end
      written
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("Transcoder is read-only")
    end

    @carry = Bytes.new(4)
    @carry_start = 0
    @carry_end = 0

    private def read_small(slice : Bytes) : Int32
      if @carry_start == @carry_end
        @carry_start = 0
        @carry_end = read(@carry)
        return 0 if @carry_end == 0
      end
      count = Math.min(slice.size, @carry_end - @carry_start)
      slice.copy_from(@carry[@carry_start, count])
      @carry_start += count
      count
    end

    @[AlwaysInline]
    private def unit_bytes : Int32
      case @source_encoding
      when .utf32? then 4
      when .utf16? then 2
      else              1
      end
    end

    private def read_unit : Int32
      input = @input
      start = @input_start
      unit = case @source_encoding
             when .utf16_be?
               (input[start].to_i32 << 8) | input[start + 1]
             when .utf16_le?
               (input[start + 1].to_i32 << 8) | input[start]
             when .utf32_be?
               (input[start].to_i64 << 24 | input[start + 1].to_i64 << 16 | input[start + 2].to_i64 << 8 | input[start + 3]).to_i32!
             when .utf32_le?
               (input[start + 3].to_i64 << 24 | input[start + 2].to_i64 << 16 | input[start + 1].to_i64 << 8 | input[start]).to_i32!
             else
               input[start].to_i32
             end
      @input_start = start + unit_bytes
      unit
    end

    private def decode_unit(unit : Int32, slice : Bytes, written : Int32) : Int32
      return encode(unit, slice, written) if @source_encoding.iso8859_1?
      if @source_encoding.utf32?
        if unit < 0 || unit > 0x10FFFF || (unit >= 0xD800 && unit <= 0xDFFF)
          slice[written] = INVALID_UNIT
          return written + 1
        end
        return encode(unit, slice, written)
      end
      if unit >= 0xD800 && unit <= 0xDBFF
        written = flush_unpaired(slice, written)
        @pending_high = unit
        return written
      end
      if unit >= 0xDC00 && unit <= 0xDFFF
        high = @pending_high
        if high < 0
          slice[written] = INVALID_UNIT
          return written + 1
        end
        @pending_high = -1
        return encode(0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00), slice, written)
      end
      written = flush_unpaired(slice, written)
      encode(unit, slice, written)
    end

    private def flush_unpaired(slice : Bytes, written : Int32) : Int32
      return written if @pending_high < 0
      @pending_high = -1
      slice[written] = INVALID_UNIT
      written + 1
    end

    # Handles the end of the source: a dangling high surrogate becomes one
    # INVALID_UNIT and every leftover byte one TRUNCATED_BYTE.
    private def finish(slice : Bytes, written : Int32) : Int32
      written = flush_unpaired(slice, written)
      while @input_start < @input_end && written < slice.size
        slice[written] = TRUNCATED_BYTE
        written += 1
        @input_start += 1
      end
      written
    end

    private def encode(code : Int32, slice : Bytes, written : Int32) : Int32
      written + UTF8.encode(code, slice[written, slice.size - written])
    end

    private def refill(needed : Int32) : Nil
      return if @eof
      remaining = @input_end - @input_start
      # The ranges can overlap, so move (memmove), never copy.
      @input[0, remaining].move_from(@input[@input_start, remaining]) if remaining > 0
      @input_start = 0
      @input_end = remaining
      while @input_end < needed
        count = @source.read(@input[@input_end, @input.size - @input_end])
        @after_source_read.try &.call
        if count == 0
          @eof = true
          return
        end
        @input_end += count
      end
    end
  end
end
