module Amber::Router
  class GlobMatch(T)
    property path : Array(String)
    property match_position : Int32

    property terminal_segment : TerminalSegment(T)
    property routed_result : RoutedResult(T)

    def initialize(@terminal_segment, @path)
      @routed_result = RoutedResult(T).new terminal_segment
      @match_position = @path.size - 1
    end

    def inspect(io : IO)
      io << "#<GlobMatch "
      io << terminal_segment.full_path
      io << ", "
      io << path
      io << ", #{match_position}>"
    end

    def to_s(io : IO)
      inspect io
    end

    def current_segment(offset = 0)
      path[match_position + offset]
    end
  end
end
