module Amber::Mica::Core
  # `ByteInput` for text formats whose input may arrive in an encoding other
  # than UTF-8: the scanner always sees UTF-8, while positions still refer
  # to the original bytes.
  #
  # A format starts transcoding either up front (after a byte order mark,
  # with `setup_transcoded_stream`) or mid-stream (after an in-band
  # declaration, with `switch_to_transcoder`). Invalid code units reach the
  # scanner as `Transcoder` marker bytes, which are never valid UTF-8; the
  # scanner reports them as `Amber::Mica::EncodingError` (see
  # `describe_transcoder_marker`) at an offset `source_offset_at` maps back
  # to the original input.
  #
  # The including type calls `account_transcoded_discard(keep)` from its
  # `discarding_input` hook, and defines `source_read_returned`, which runs
  # after every read from the source under a transcoder (where to check a
  # deadline).
  module TextInput
    include ByteInput

    # Called after every read a `Transcoder` makes from the source.
    private abstract def source_read_returned : Nil

    @transcoded_from : Encoding? = nil
    @transcode_origin = 0_i64
    @source_bytes_before_buffer = 0_i64
    # Cache for `source_offset_at` on transcoded input: the last decoded
    # position answered (absolute) and its source size from `from`.
    @offset_cache_absolute = -1_i64
    @offset_cache_from = -1_i64
    @offset_cache_size = 0_i64
    # Decoded bytes examined by `source_offset_at`, for work accounting.
    @offset_steps = 0_i64

    # Reads *transcoder*'s output as the whole input; *mark_size* source bytes
    # (a byte order mark) came before it.
    private def setup_transcoded_stream(transcoder : Transcoder, mark_size : Int32) : Nil
      transcoder.after_source_read = -> { source_read_returned }
      setup_stream(transcoder, Bytes.empty, mark_size)
      @transcoded_from = transcoder.source_encoding
      @transcode_origin = 0_i64
      @source_bytes_before_buffer = 0_i64
    end

    # Reads the rest of the input, from the current position on, through a
    # `Transcoder` from *encoding*. Used after an in-band encoding
    # declaration names an encoding that is not UTF-8. Everything before the
    # current position must have been ASCII.
    private def switch_to_transcoder(encoding : Encoding) : Nil
      io = @io
      # Folding the bytes before the switch passes over them. A stream
      # prepays its discards as it reads; in-memory input is charged here.
      moving_input(@pos.to_i64) unless io
      discarding_input(@pos)
      rest = @buffer[@pos, @limit - @pos]
      source = io || IO::Memory.new(rest, writable: false)
      # Carrying the buffered bytes copies them here and in the transcoder:
      # charged first.
      moving_input(2_i64 * rest.size) if io
      carried = io ? rest.dup : Bytes.empty
      @input_bytes -= rest.size
      @base_offset += @pos
      @transcoded_from = encoding
      @transcode_origin = @base_offset
      @source_bytes_before_buffer = 0_i64
      @offset_cache_from = -1_i64
      transcoder = Transcoder.new(source, encoding, carried)
      transcoder.after_source_read = -> { source_read_returned }
      @io = transcoder
      @io_eof = false
      @buffer = Bytes.new(ByteInput::INITIAL_BUFFER_SIZE)
      @pos = 0
      @limit = 0
      @mark = 0
      @pin = -1
    end

    # Adds the source size of the decoded bytes `@buffer[0, keep]` that are
    # about to be discarded, so later offsets map back exactly. Each byte is
    # counted once. Returns the bytes examined, for the format to charge.
    private def account_transcoded_discard(keep : Int32) : Int32
      encoding = @transcoded_from
      return 0 unless encoding
      from = @transcode_origin > @base_offset ? (@transcode_origin - @base_offset).to_i32 : 0
      return 0 unless from < keep
      @source_bytes_before_buffer += Transcoder.source_size(encoding, @buffer[from, keep - from])
      @offset_cache_from = -1_i64
      keep - from
    end

    # Returns the offset in the original input of byte *pos* of *buffer*,
    # whose first byte is at decoded offset *base*.
    #
    # On transcoded input the decoded bytes between the buffer start (or the
    # transcoding origin) and *pos* are mapped back to source bytes. The last
    # answer is cached, so asking for positions that only move forward costs
    # the distance moved, not the distance from the buffer start; the bytes
    # examined are counted in `@offset_steps` for work accounting.
    private def source_offset_at(buffer : Bytes, pos : Int32, base : Int64) : Int64
      source_offset_at(buffer, pos, base) { }
    end

    # Decoded bytes mapped between two calls of the step block of
    # `source_offset_at`.
    OFFSET_STEP_CHUNK = 65_536

    # Same, calling the block with the decoded bytes examined at least
    # every OFFSET_STEP_CHUNK bytes and before they are
    # mapped, so a work meter can stop a long mapping partway.
    private def source_offset_at(buffer : Bytes, pos : Int32, base : Int64, & : Int32 ->) : Int64
      absolute = base + pos
      encoding = @transcoded_from
      return @source_prefix_bytes + absolute if encoding.nil? || absolute <= @transcode_origin
      from = @transcode_origin > base ? (@transcode_origin - base).to_i32 : 0
      from_absolute = base + from
      scan_from = from
      size = 0_i64
      if @offset_cache_from == from_absolute && @offset_cache_absolute >= from_absolute && @offset_cache_absolute <= absolute
        scan_from = (@offset_cache_absolute - base).to_i32
        size = @offset_cache_size
      end
      index = scan_from
      while index < pos
        chunk_end = pos - index > OFFSET_STEP_CHUNK ? index + OFFSET_STEP_CHUNK : pos
        yield chunk_end - index
        @offset_steps += chunk_end - index
        size += Transcoder.source_size(encoding, buffer[index, chunk_end - index])
        index = chunk_end
      end
      @offset_cache_from = from_absolute
      @offset_cache_absolute = absolute
      @offset_cache_size = size
      @source_prefix_bytes + @transcode_origin + @source_bytes_before_buffer + size
    end

    # Returns a description when *lead* is a `Transcoder` marker byte in
    # transcoded input, or nil.
    private def describe_transcoder_marker(lead : UInt8) : String?
      encoding = @transcoded_from
      return unless encoding
      if lead == Transcoder::INVALID_UNIT
        encoding.utf16? ? "Unpaired UTF-16 surrogate" : "Invalid #{encoding.label} code unit"
      elsif lead == Transcoder::TRUNCATED_BYTE
        "Input ends inside a #{encoding.label} code unit"
      end
    end
  end
end
