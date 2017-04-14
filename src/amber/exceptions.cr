module Amber
  module Exceptions
    class DuplicateRouteError < Exception
      def initialize(route : Route)
        super("Route: #{route.verb} #{route.resource} is duplicated.")
      end
    end

    class RouteNotFound < Exception
      def initialize(request)
        super("The request was not found.")
      end
    end

    class Forbidden < Exception
      def initialize(message)
        super("The request was not found.")
      end
    end
  end
end
