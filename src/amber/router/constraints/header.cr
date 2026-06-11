require "../constraint"

module Amber::Router::Constraints
  # Matches requests where a specific header has the expected value.
  class Header
    include Amber::Router::Constraint

    def initialize(@header_name : String, @expected_value : String)
    end

    def matches?(request : HTTP::Request) : Bool
      if actual = request.headers[@header_name]?
        actual == @expected_value
      else
        false
      end
    end
  end
end
