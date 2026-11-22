require "colorize"

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

    class Environment < Exception
      def initialize(path, environment)
        super("Environment file not found for #{path}#{environment}")
      end
    end

    # NOTE: Any exceptions which aren't part of and http request cycle shouldn't inherit from Base.
    class EncryptionKeyMissing < Exception
      def initialize(file_path, encrypt_env)
        super(%(Encryption key not found. Please set it via '#{file_path}' or 'ENV[#{encrypt_env}]'.\n\n))
      end
    end

    # Raised when an app built with `-Dwithout_openssl` is configured to use
    # TLS. That flag builds an app that links no OpenSSL, for apps that sit
    # behind a proxy which terminates TLS; an app that serves HTTPS itself or
    # sends mail over STARTTLS is built without the flag.
    class TLSNotCompiledIn < Exception
      def initialize(feature : String)
        super("#{feature} needs TLS, and this app was built with -Dwithout_openssl. Build it without that flag to use TLS.")
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

    # Raised when a request body or query cannot be parsed. Answered with
    # `400 Bad Request`.
    class BadRequest < Base
      def initialize(message : String)
        @status_code = 400
        super(message)
      end
    end

    # Raised when a request body declares a `charset` that is not a label of
    # the WHATWG Encoding Standard. Answered with `415 Unsupported Media
    # Type`. It is a `BadRequest` so that everything that handles a rejected
    # body handles this one.
    class UnsupportedCharset < BadRequest
      def initialize
        super("The request body's declared charset is not supported")
        @status_code = 415
      end
    end

    # Raised when request parameters exceed a bound in
    # `Amber::Configuration::ParamsConfig`. Answered with `400 Bad Request`.
    class ParameterLimitExceeded < BadRequest
      getter limit_name : String
      getter limit_value : Int64

      def initialize(@limit_name : String, limit_value : Int)
        @limit_value = limit_value.to_i64
        super("Request parameters exceed the #{@limit_name} limit of #{@limit_value}.")
      end

      def initialize(message : String, @limit_name : String, limit_value : Int)
        @limit_value = limit_value.to_i64
        super(message)
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
        getter errors

        def initialize(@errors : Array(Amber::Validators::Error))
          super("Validation failed. #{@errors}")
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
