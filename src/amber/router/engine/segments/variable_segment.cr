module Amber::Router
  class VariableSegment(T) < Segment(T)
    @has_constraint : Bool

    def initialize(segment, @pattern : Regex? = nil)
      super segment
      @has_constraint = !@pattern.nil?
    end

    @[AlwaysInline]
    def match?(segment : String) : Bool
      return true unless @has_constraint
      !!(segment =~ @pattern)
    end

    def parametric? : Bool
      true
    end

    def parameter : String
      segment[1..-1]
    end
  end
end
