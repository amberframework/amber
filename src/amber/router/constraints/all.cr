require "../constraint"

module Amber::Router::Constraints
  # Matches a request only when every one of its constraints does. Nested
  # `constraint` blocks combine through it, so an inner block narrows the
  # outer one instead of replacing it.
  class All
    include Amber::Router::Constraint

    getter list_of_constraints : Array(Amber::Router::Constraint)

    def initialize(@list_of_constraints : Array(Amber::Router::Constraint))
    end

    def matches?(request : HTTP::Request) : Bool
      list_of_constraints.all?(&.matches?(request))
    end
  end
end
