require "../constraint"

module Amber::Router::Constraints
  # Matches requests against an exact host value from the Host header.
  class Host
    include Amber::Router::Constraint

    def initialize(@host : String)
    end

    def matches?(request : HTTP::Request) : Bool
      if host_header = request.headers["Host"]?
        # Strip port if present for comparison
        actual_host = host_header.split(':').first
        actual_host == @host
      else
        false
      end
    end
  end
end
