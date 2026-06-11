module Backtracer
  class Backtrace
    getter frames : Array(Frame)

    def initialize(@frames = [] of Frame)
    end

    def_equals_and_hash @frames

    def to_s(io : IO) : Nil
      @frames.join(io, '\n')
    end

    def inspect(io : IO) : Nil
      io << "#<Backtrace: "
      @frames.join(io, ", ", &.inspect(io))
      io << '>'
    end
  end
end

require "./backtrace/*"
