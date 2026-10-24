module Amber::Router::Parsers
  # Wraps an IO and raises `Amber::Exceptions::ParameterLimitExceeded` once
  # more than *limit* bytes have been read through it.
  class BoundedIO < IO
    getter bytes_read : Int64 = 0_i64

    def initialize(@io : IO, @limit : Int64, @limit_name : String)
    end

    def read(slice : Bytes) : Int32
      count = @io.read(slice)
      @bytes_read += count
      if @bytes_read > @limit
        raise Amber::Exceptions::ParameterLimitExceeded.new(@limit_name, @limit)
      end
      count
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("BoundedIO is read-only")
    end
  end
end
