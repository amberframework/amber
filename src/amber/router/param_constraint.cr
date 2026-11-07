module Amber::Router
  # A rule that one route parameter's path segment must pass before its route
  # can match, such as "digits only" for `:id` in `/posts/:id`.
  #
  # The rule sees the raw segment, before percent-decoding, and judges the
  # whole segment. The built-in rules in `ParamConstraints` read each byte
  # once, so matching takes time linear in the segment's length and uses no
  # regular-expression engine.
  #
  # A custom rule is a type that includes this module:
  #
  # ```
  # struct EvenNumber
  #   include Amber::Router::ParamConstraint
  #
  #   def matches?(segment : String) : Bool
  #     if number = segment.to_i?
  #       number.even?
  #     else
  #       false
  #     end
  #   end
  #
  #   def to_s(io : IO) : Nil
  #     io << "even_number"
  #   end
  # end
  #
  # get "/pages/:number", PagesController, :show, {"number" => EvenNumber.new}
  # ```
  module ParamConstraint
    # Returns `true` when *segment* satisfies this rule.
    abstract def matches?(segment : String) : Bool

    # Writes the short label that route listings and `Route#to_json` show for
    # this rule.
    abstract def to_s(io : IO) : Nil

    # Returns `true` when the segment of *path* that starts at *byte_offset*
    # and is *bytesize* bytes long satisfies this rule. The router calls this
    # while it walks a path; the built-in rules override it to read the bytes
    # in place instead of copying the segment.
    def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
      matches?(path.byte_slice(byte_offset, bytesize))
    end
  end
end
