module Amber::Router
  # Allocation-free view over one slash-delimited segment in a String.
  struct SegmentView
    getter source : String
    getter byte_offset : Int32
    getter bytesize : Int32

    def initialize(@source, @byte_offset = 0, @bytesize = source.bytesize)
    end

    def bytes : Bytes
      Bytes.new(source.to_unsafe + byte_offset, bytesize, read_only: true)
    end

    def ==(other : self) : Bool
      bytesize == other.bytesize && bytes == other.bytes
    end

    def hash(hasher)
      hasher.bytes(bytes)
    end
  end

  record SpanGlobMatch(T), routed_result : RoutedResult(T), match_end : Int32
end
