require "./base"
require "../exceptions/page"

module Amber::Controller
  class Error < Base
    def initialize(@context : HTTP::Server::Context, @ex : Exception)
      super(@context)
      @context.response.content_type = content_type
    end

    module Helpers
      def bad_request
        response_format
      end

      def forbidden
        response_format
      end

      def not_found
        response_format
      end

      def internal_server_error
        response_format
      end

      # The response's media type: JSON or HTML when the first entry of the
      # request's `Accept` header names one (parameters and letter case
      # aside), and plain text otherwise. It is chosen from these three, so
      # the client's header is never echoed back.
      private def content_type
        accept = context.request.headers["Accept"]?
        return "text/plain" unless accept

        case accept.split(",").first.split(";").first.strip.downcase
        when "application/json" then "application/json"
        when "text/html"        then "text/html"
        else                         "text/plain"
        end
      end

      private def response_format
        case content_type
        when "application/json"
          {"error": @ex.message}.to_json
        when "text/html"
          html_response
        else
          @ex.message
        end
      end

      private def html_response
        if Amber.env.development?
          Amber::Exceptions::Page.new(context, @ex)
        else
          "<html><body><pre>#{HTML.escape(@ex.message.to_s)}</pre></body></html>"
        end
      end
    end

    include Amber::Controller::Error::Helpers
  end
end
