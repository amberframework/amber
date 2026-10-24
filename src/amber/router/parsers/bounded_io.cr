module Amber::Router::Parsers
  # Wraps an IO and raises `Amber::Exceptions::ParameterLimitExceeded` once
  # more than *limit* bytes have been consumed through it.
  #
  # A segment limit can be opened on top of the total, for example around a
  # multipart part's headers, so one long header line is rejected as soon as
  # it passes the segment allowance.
  class BoundedIO < IO
    getter bytes_read : Int64 = 0_i64

    @segment_limit : Int64? = nil
    @segment_name : String = ""
    @segment_bytes : Int64 = 0_i64

    def initialize(@io : IO, @limit : Int64, @limit_name : String)
    end

    # Starts counting a segment that may consume at most *limit* bytes.
    def begin_segment(limit : Int, limit_name : String) : Nil
      @segment_limit = limit.to_i64
      @segment_name = limit_name
      @segment_bytes = 0_i64
    end

    def end_segment : Nil
      @segment_limit = nil
    end

    def read(slice : Bytes) : Int32
      count = @io.read(slice)
      charge(count)
      count
    end

    # Peeking does not consume, so it is not charged; `skip` is. The peeked
    # bytes are trimmed to one byte past the remaining allowance, so a reader
    # that scans the peek buffer (such as `gets`) cannot copy more than that
    # before its `skip` trips the limit.
    def peek : Bytes?
      peeked = @io.peek
      return peeked unless peeked

      allowance = @limit - @bytes_read
      if segment_limit = @segment_limit
        allowance = Math.min(allowance, segment_limit - @segment_bytes)
      end
      visible = Math.min(peeked.size.to_i64, Math.max(allowance, 0_i64) + 1)
      peeked[0, visible.to_i32]
    end

    def skip(bytes_count : Int) : Nil
      charge(bytes_count)
      @io.skip(bytes_count)
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("BoundedIO is read-only")
    end

    private def charge(count : Int) : Nil
      @bytes_read += count
      if @bytes_read > @limit
        raise Amber::Exceptions::ParameterLimitExceeded.new(@limit_name, @limit)
      end

      if segment_limit = @segment_limit
        @segment_bytes += count
        if @segment_bytes > segment_limit
          raise Amber::Exceptions::ParameterLimitExceeded.new(@segment_name, segment_limit)
        end
      end
    end
  end
end
