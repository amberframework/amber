module Amber::Router::Parsers
  # :nodoc:
  # Reads each IO in *list_of_readers* to its end, in order, as one stream.
  # Amber uses it to hand back a request body it read in pieces.
  class ChainedReader < IO
    @index = 0

    def initialize(@list_of_readers : Array(IO))
    end

    def read(slice : Bytes) : Int32
      return 0 if slice.empty?

      while @index < @list_of_readers.size
        count = @list_of_readers[@index].read(slice)
        return count if count > 0
        @index += 1
      end
      0
    end

    def write(slice : Bytes) : Nil
      raise IO::Error.new("ChainedReader is read-only")
    end
  end
end
