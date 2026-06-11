module Amber::Router
  # Represents a match-anything url segment.
  #
  # In the url `/products/:23/*`, the third segment, `*` is a glob segment.
  class GlobSegment(T) < Segment(T)
    def match?(curious_segment : String)
      true
    end

    def parametric?
      parameter.size > 0
    end

    def parameter
      @segment[1..-1]
    end
  end
end
