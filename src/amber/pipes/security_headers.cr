require "./base"

module Amber
  module Pipe
    # Adds browser security headers to every response that passes through the
    # pipeline: `X-Content-Type-Options`, `X-Frame-Options`, a
    # `frame-ancestors` `Content-Security-Policy`, `Referrer-Policy`,
    # `Permissions-Policy`, `Cross-Origin-Opener-Policy`, and, on HTTPS
    # requests, `Strict-Transport-Security`.
    #
    # The values come from the `security_headers` settings section
    # (`Amber::Configuration::SecurityHeadersConfig`), which has secure
    # defaults and is overridden per environment in
    # `config/environments/<env>.yml` or with `AMBER_SECURITY_HEADERS_*`
    # variables.
    #
    # The pipe writes its headers before the rest of the pipeline runs and
    # never replaces a header that is already on the response, so a pipe
    # plugged earlier keeps its value and a controller that assigns one of
    # these headers has the final word.
    #
    # Whether a request is HTTPS is decided by `HTTP::Request#https?`, the
    # same method the cookie jar uses for the `Secure` flag, so
    # `Strict-Transport-Security` and secure cookies always agree.
    #
    # ```
    # pipeline :web do
    #   plug Amber::Pipe::Error.new
    #   plug Amber::Pipe::Logger.new
    #   plug Amber::Pipe::SecurityHeaders.new
    #   plug Amber::Pipe::Session.new
    # end
    # ```
    class SecurityHeaders < Base
      STRICT_TRANSPORT_SECURITY = "Strict-Transport-Security"

      @config : Amber::Configuration::SecurityHeadersConfig?

      # Creates the pipe. Without *config* it reads
      # `Amber.settings.security_headers` on each request, so it follows the
      # loaded environment settings.
      def initialize(@config : Amber::Configuration::SecurityHeadersConfig? = nil)
      end

      def call(context : HTTP::Server::Context)
        write_headers(context)
        call_next(context)
      end

      # Writes the configured headers to the response of *context*, leaving a
      # header that is already present as it is. `Amber::Pipe::Pipeline` also
      # calls it for a request that matched no route, which never reaches a
      # pipeline's pipes.
      def write_headers(context : HTTP::Server::Context) : Nil
        config = current_config
        response_headers = context.response.headers

        config.list_of_headers.each do |header_name, value|
          set_unless_present(response_headers, header_name, value)
        end

        if config.sends_strict_transport_security? && context.request.https?
          set_unless_present(response_headers, STRICT_TRANSPORT_SECURITY, config.strict_transport_security)
        end
      end

      private def current_config : Amber::Configuration::SecurityHeadersConfig
        @config || Amber.settings.security_headers
      end

      private def set_unless_present(headers : HTTP::Headers, header_name : String, value : String) : Nil
        headers[header_name] = value unless headers.has_key?(header_name)
      end
    end
  end
end
