require "colorize"

module Amber
  module Exceptions
    class Base < Exception
    end

    class Environment < Exception
      def initialize(path, environment)
        super("Environment file not found for #{path}#{environment}")
      end
    end

    # NOTE: Any exceptions which aren't part of and http request cycle shouldn't inherit from Base.
    class EncryptionKeyMissing < Exception
      def initialize(file_path, encrypt_env)
        super(%(Encryption key not found. Please set it via '#{file_path}' or 'ENV[#{encrypt_env}]'.\n\n).colorize(:yellow).to_s)
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
        super("The request was not found. #{request.method} - #{request.path}")
      end
    end

    class Forbidden < Base
      def initialize(message : String?)
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
