module Amber
  module Exceptions
    class DuplicateRouteError < Exception
      def initialize(route : Route)
        super("Route: #{route.verb} #{route.path} is duplicated.")
      end
    end
  end
end