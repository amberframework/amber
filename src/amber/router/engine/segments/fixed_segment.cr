module Amber::Router
  # Represents a must-match url segment.
  #
  # In the url `/products/:23/*`, the first segment, `products` is a fixed segment.
  class FixedSegment(T) < Segment(T)
  end
end
