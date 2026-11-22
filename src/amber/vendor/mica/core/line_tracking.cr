module Amber::Mica::Core
  # Line and column tracking for text formats, included next to `ByteInput`.
  #
  # The scanner calls `record_line_break` after each line end it consumes
  # (each format decides what a line end is). Columns are not counted while
  # scanning: `column_at` counts the characters (UTF-8 lead bytes) between
  # the line start and a position when one is asked for. A cache of the last
  # answer makes repeated questions on the same line cost only the distance
  # moved, so asking for the position after every event stays linear in the
  # input size even on a single-line document.
  #
  # Line and column numbers saturate at `Int32::MAX` (the byte offset in a
  # `Position` stays exact), so a stream of any length cannot overflow
  # them.
  module LineTracking
    @line = 1
    @line_start = 0_i64
    @column_offset = 0_i64
    @column_cache_offset = -1_i64
    @column_cache_value = 0_i64
    @column_cache_line_start = -1_i64
    # Bytes examined by `column_at`, for work accounting.
    @column_steps = 0_i64

    # Records a line end; the next line starts at decoded offset
    # *next_line_start*.
    @[AlwaysInline]
    private def record_line_break(next_line_start : Int64) : Nil
      @line += 1 if @line < Int32::MAX
      @line_start = next_line_start
      @column_offset = 0_i64
    end

    # Folds the characters between the line start and the end of the bytes
    # about to be discarded (`buffer[0, keep]`, first byte at decoded offset
    # *base*) into `@column_offset`, so columns stay exact after the buffer
    # moves. Each discarded byte is counted at most once. Returns the bytes
    # examined, for the format to charge.
    private def fold_discarded_columns(buffer : Bytes, keep : Int32, base : Int64) : Int32
      discard_end = base + keep
      return 0 unless @line_start < discard_end
      from = Math.max(@line_start - base, 0_i64).to_i32
      discarded = buffer[from, keep - from]
      # Characters are the bytes that are not UTF-8 continuation bytes.
      @column_offset += discarded.size - discarded.count { |byte| byte & 0xC0 == 0x80 }
      @line_start = discard_end
      @column_cache_offset = -1_i64
      discarded.size
    end

    # Returns the 1-based column of byte *pos* of *buffer* (first byte at
    # decoded offset *base*) on the current line.
    private def column_at(buffer : Bytes, pos : Int32, base : Int64) : Int32
      column_at(buffer, pos, base) { }
    end

    # Bytes counted between two calls of the step block of `column_at`.
    POSITION_STEP_CHUNK = 65_536

    # Same, calling the block with the bytes examined at least every
    # POSITION_STEP_CHUNK bytes and before the count goes on, so a work
    # meter can stop a long count partway.
    private def column_at(buffer : Bytes, pos : Int32, base : Int64, & : Int32 ->) : Int32
      absolute = base + pos
      return saturated_column(absolute - @line_start + 1) if @line_start < base || @line_start > absolute
      start = (@line_start - base).to_i32
      column = 1_i64 + @column_offset
      cached = @column_cache_offset
      if @column_cache_line_start == @line_start && cached >= @line_start && cached >= base && cached <= absolute
        start = (cached - base).to_i32
        column = @column_cache_value
      end
      index = start
      while index < pos
        chunk_end = pos - index > POSITION_STEP_CHUNK ? index + POSITION_STEP_CHUNK : pos
        yield chunk_end - index
        @column_steps += chunk_end - index
        counted = buffer[index, chunk_end - index]
        column += counted.size - counted.count { |byte| byte & 0xC0 == 0x80 }
        index = chunk_end
      end
      @column_cache_offset = absolute
      @column_cache_value = column
      @column_cache_line_start = @line_start
      saturated_column(column)
    end

    private def saturated_column(column : Int64) : Int32
      Math.min(column, Int32::MAX.to_i64).to_i32
    end
  end
end
