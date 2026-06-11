module Amber::Router
  # Abstract constraint that can inspect the full HTTP request.
  # Implement this module to create custom request-level constraints
  # for route matching (e.g., subdomain, host, header matching).
  module Constraint
    abstract def matches?(request : HTTP::Request) : Bool
  end
end
