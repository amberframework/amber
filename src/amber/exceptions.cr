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

    module Validator
      class MissingValidationRules < Exception
        def initialize
          super("No validation rules defined for this validator.")
        end
      end

      class ValidationFailed < Exception
        def initialize(errors)
          super("Validation failed. #{errors}s")
        end
      end
    end
  end
end
