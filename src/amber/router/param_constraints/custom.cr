require "../param_constraint"

module Amber::Router::ParamConstraints
  # Matches a segment for which the given block returns `true`. Use it for a
  # one-off rule; a rule used in several places reads better as its own type
  # that includes `Amber::Router::ParamConstraint`.
  #
  # The block runs on every request that reaches the route's segment, so keep
  # it linear in the segment's length.
  #
  # ```
  # json_file = Amber::Router::ParamConstraints::Custom.new("json_file") do |segment|
  #   segment.ends_with?(".json")
  # end
  # get "/files/:name", FilesController, :show, {"name" => json_file}
  # ```
  struct Custom
    include Amber::Router::ParamConstraint

    getter label : String
    @check : String -> Bool

    def initialize(@label : String, &@check : String -> Bool)
    end

    def matches?(segment : String) : Bool
      @check.call(segment)
    end

    def to_s(io : IO) : Nil
      io << @label
    end
  end
end
