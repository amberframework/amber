module Amber
  module Exceptions
    class DuplicateRouteError < Exception
      def initialize(route : Route)
        super("Route: #{route.verb} #{route.resource} is duplicated.")
      end
    end

    class RouteNotFound < Exception
      def initialize(request)
        super("The request was not found. #{request.method} - #{request.path}")
      end
    end

    class Forbidden < Exception
      def initialize(message)
        super("The request was not found.")
      end
    end

    module Controller
      class Redirect < Exception
        def initialize(location)
          super("Cannot redirect to this location: #{location}")
        end
      end
    end

    module Validator
      class ValidationFailed < Exception
        def initialize(errors)
          super("Validation failed. #{errors}")
        end
      end

      class InvalidParam < Exception
        def initialize(param)
          super("The #{param} param was not found, make sure is typed correctly.")
        end
      end
    end
  end
end
