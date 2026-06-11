module Amber::Router
  abstract class Segment(T)
    property route_set : RouteSet(T)
    property segment : String

    def initialize(@segment)
      @route_set = RouteSet(T).new(false)
    end

    def formatted_s(*, ts = 0)
      tab = "  " * ts
      String.build do |str|
        str << "#{tab}|--#{segment}\n"
        if route_set.routes?
          str << route_set.formatted_s ts: ts + 1
        end
      end
    end

    def match?(curious_segment : String) : Bool
      @segment == curious_segment
    end

    def literal_match?(curious_segment : String) : Bool
      @segment == curious_segment
    end

    def parametric? : Bool
      false
    end

    def parameter : String
      @segment
    end
  end
end

require "./segments/terminal_segment"
require "./segments/fixed_segment"
require "./segments/variable_segment"
require "./segments/glob_segment"
