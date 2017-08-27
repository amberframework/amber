module Amber
  module Exceptions
    class Base < Exception
      getter status_code : Int32 = 500

      def set_response(response)
        response.headers["Content-Type"] = "text/plain"
        response.print message
        response.status_code = status_code
      end
    end

    # Raised when storing more than 4K of session data.
    class CookieOverflow < Base
    end

    class InvalidSignature < Base
    end

    class InvalidMessage < Base
    end

    class DuplicateRouteError < Base
      def initialize(route : Route)
        super("Route: #{route.verb} #{route.resource} is duplicated.")
      end
    end

    class RouteNotFound < Base
      def initialize(request)
        @status_code = 404
        super("The request was not found. #{request.method} - #{request.path}")
      end
    end

    class Forbidden < Base
      def initialize(message : String?)
        @status_code = 403
        super(message || "Action is Forbidden.")
      end
    end

    module Controller
      class Redirect < Base
        def initialize(location)
          super("Cannot redirect to this location: #{location}")
        end
      end
    end

    module Validator
      class ValidationFailed < Base
        def initialize(errors)
          super("Validation failed. #{errors}")
        end
      end

      class InvalidParam < Base
        def initialize(param)
          super("The #{param} param was not found, make sure is typed correctly.")
        end
      end
    end
  end
end
