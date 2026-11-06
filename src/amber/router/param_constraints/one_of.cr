require "../param_constraint"

module Amber::Router::ParamConstraints
  # Matches a segment equal to one of the listed values.
  #
  # ```
  # get "/posts/:state", PostsController, :index,
  #   {"state" => Amber::Router::ParamConstraints::OneOf.new("draft", "published")}
  # ```
  struct OneOf
    include Amber::Router::ParamConstraint

    @list_of_values : Array(String)
    @set_of_values : Set(String)

    def initialize(*values : String)
      @list_of_values = values.to_a
      @set_of_values = @list_of_values.to_set
    end

    # The values this rule accepts, in the order given. A copy: changing it does
    # not change the rule.
    def list_of_values : Array(String)
      @list_of_values.dup
    end

    def matches?(segment : String) : Bool
      @set_of_values.includes?(segment)
    end

    def to_s(io : IO) : Nil
      io << "one_of("
      @list_of_values.join(io, '|')
      io << ')'
    end
  end
end
