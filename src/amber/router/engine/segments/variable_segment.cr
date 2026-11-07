module Amber::Router
  class VariableSegment(T) < Segment(T)
    @parameter : String
    @constraint : ParamConstraint?

    def initialize(segment, @constraint : ParamConstraint? = nil)
      super segment
      @parameter = segment[1..-1]
    end

    @[AlwaysInline]
    def match?(segment : String) : Bool
      if constraint = @constraint
        constraint.matches?(segment)
      else
        true
      end
    end

    @[AlwaysInline]
    def match_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
      if constraint = @constraint
        constraint.matches_span?(path, byte_offset, bytesize)
      else
        true
      end
    end

    def parametric? : Bool
      true
    end

    def parameter : String
      @parameter
    end
  end
end
