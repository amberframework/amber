module Amber::Router
  class VariableSegment(T) < Segment(T)
    @has_constraint : Bool
    @parameter : String

    def initialize(segment, @pattern : Regex? = nil)
      super segment
      @parameter = segment[1..-1]
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
      @parameter
    end
  end
end
