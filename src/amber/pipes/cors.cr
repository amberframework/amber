require "./base"

module Amber
  module Pipe
    module Headers
      VARY              = "Vary"
      ORIGIN            = "Origin"
      X_ORIGIN          = "X-Origin"
      REQUEST_METHOD    = "Access-Control-Request-Method"
      REQUEST_HEADERS   = "Access-Control-Request-Headers"
      ALLOW_EXPOSE      = "Access-Control-Expose-Headers"
      ALLOW_ORIGIN      = "Access-Control-Allow-Origin"
      ALLOW_METHODS     = "Access-Control-Allow-Methods"
      ALLOW_HEADERS     = "Access-Control-Allow-Headers"
      ALLOW_CREDENTIALS = "Access-Control-Allow-Credentials"
      ALLOW_MAX_AGE     = "Access-Control-Max-Age"
    end

    class CORS < Base
      alias OriginRule = Proc(String, Bool)
      alias OriginList = Array(String | OriginRule)
      alias OriginType = Array(String | Regex)
      FORBIDDEN     = "Forbidden for invalid origins, methods or headers"
      ALLOW_METHODS = %w(POST PUT PATCH DELETE)
      ALLOW_HEADERS = %w(Accept Content-Type)

      property origins, headers, methods, credentials, max_age
      @origin : Origin

      def initialize(
        @origins : OriginList = OriginList{"*"},
        @methods = ALLOW_METHODS,
        @headers = ALLOW_HEADERS,
        @credentials = false,
        @max_age : Int32? = 0,
        @expose_headers : Array(String)? = nil,
        @vary : String? = nil,
      )
        @origin = Origin.new(origins)
      end

      # Lists plain origins. An app that uses this form links no regex engine.
      def self.new(
        origins : Array(String),
        methods = ALLOW_METHODS,
        headers = ALLOW_HEADERS,
        credentials = false,
        max_age : Int32? = 0,
        expose_headers : Array(String)? = nil,
        vary : String? = nil,
      )
        origin_rules = OriginList.new(origins.size)
        origins.each { |origin| origin_rules << origin }

        new(origin_rules, methods, headers, credentials, max_age, expose_headers, vary)
      end

      # Accepts `Regex` origins. This overload compiles only in an app that calls
      # it, so an app that lists plain origins links no regex engine.
      def self.new(
        origins : OriginType,
        methods = ALLOW_METHODS,
        headers = ALLOW_HEADERS,
        credentials = false,
        max_age : Int32? = 0,
        expose_headers : Array(String)? = nil,
        vary : String? = nil,
      )
        origin_rules = OriginList.new(origins.size)
        origins.each do |origin|
          if origin.is_a?(String)
            origin_rules << origin
          else
            origin_rules << OriginRule.new { |request_origin| origin.matches?(request_origin) }
          end
        end

        new(origin_rules, methods, headers, credentials, max_age, expose_headers, vary)
      end

      def call(context : HTTP::Server::Context)
        return call_next(context) unless @origin.origin_header?(context.request)

        if @origin.match?(context.request)
          is_preflight_request = preflight?(context)
          put_expose_header(context.response)
          Preflight.process(context, self) if is_preflight_request
          put_response_headers(context.response)
          call_next(context) unless is_preflight_request
        else
          forbidden(context)
        end
      end

      def forbidden(context)
        context.response.headers["Content-Type"] = "text/plain"
        context.response.respond_with_status 403
      end

      private def put_expose_header(response)
        response.headers[Headers::ALLOW_EXPOSE] = @expose_headers.as(Array).join(",") if @expose_headers
      end

      private def put_response_headers(response)
        response.headers[Headers::ALLOW_CREDENTIALS] = @credentials.to_s if @credentials
        response.headers[Headers::ALLOW_ORIGIN] = @origin.request_origin.not_nil!
        response.headers[Headers::VARY] = vary unless @origin.any_origin?
      end

      private def vary
        String.build do |str|
          str << Headers::ORIGIN
          str << "," << @vary if @vary
        end
      end

      private def preflight?(context)
        context.request.method == "OPTIONS"
      end
    end

    module Preflight
      extend self

      def process(context, cors)
        return cors.forbidden(context) unless valid?(context, cors)
        put_preflight_headers(context.request, context.response, cors.max_age)
      end

      def valid?(context, cors)
        valid_method?(context.request, cors.methods) &&
          valid_headers?(context.request, cors.headers)
      end

      def put_preflight_headers(request, response, max_age)
        response.headers[Headers::ALLOW_METHODS] = request.headers[Headers::REQUEST_METHOD]
        response.headers[Headers::ALLOW_HEADERS] = request.headers[Headers::REQUEST_HEADERS]
        response.headers[Headers::ALLOW_MAX_AGE] = max_age.to_s if max_age
        response.content_length = 0
        response.flush
      end

      def valid_method?(request, methods)
        methods.includes? request.headers[Headers::REQUEST_METHOD]?
      end

      def valid_headers?(request, headers)
        request_headers = request.headers[Headers::REQUEST_HEADERS]?
        return false if request_headers.nil? || request_headers.empty?

        headers.any? do |header|
          request_headers.downcase.split(',').includes? header.downcase
        end
      end
    end

    struct Origin
      getter request_origin : String?

      def initialize(@origins : CORS::OriginList)
      end

      def match?(request)
        return false if @origins.empty?
        return false unless origin_header?(request)
        return true if any_origin?

        origin_from_request = request_origin
        return false unless origin_from_request

        @origins.any? do |origin|
          origin.is_a?(String) ? origin == origin_from_request : origin.call(origin_from_request)
        end
      end

      def any_origin?
        @origins.includes? "*"
      end

      protected def origin_header?(request)
        @request_origin = request.headers[Headers::ORIGIN]? || request.headers[Headers::X_ORIGIN]?
      end
    end
  end
end
