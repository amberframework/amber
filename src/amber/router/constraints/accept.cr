require "../constraint"

module Amber::Router::Constraints
  # Matches requests whose Accept header contains a versioned media type.
  # Parses Accept headers like "application/vnd.myapp.v1+json" to extract
  # the version string and match against an expected version.
  class Accept
    include Amber::Router::Constraint

    def initialize(@media_type : String, @version : String)
    end

    def matches?(request : HTTP::Request) : Bool
      if accept = request.headers["Accept"]?
        # Match patterns like: application/vnd.myapp.v1+json
        accept.includes?("#{@media_type}.#{@version}")
      else
        false
      end
    end
  end
end
