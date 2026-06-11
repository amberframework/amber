require "../constraint"

module Amber::Router::Constraints
  # Matches requests whose Host header begins with the given subdomain.
  class Subdomain
    include Amber::Router::Constraint

    def initialize(@subdomain : String)
    end

    def matches?(request : HTTP::Request) : Bool
      if host_header = request.headers["Host"]?
        # Strip port if present
        host = host_header.split(':').first
        host.starts_with?("#{@subdomain}.")
      else
        false
      end
    end
  end
end
