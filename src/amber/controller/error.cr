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

      private def content_type
        if context.request.headers["Accept"]?
          request.headers["Accept"].split(",").first
        else
          "text/plain"
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
        if Amber.env == :development
          Amber::Exceptions::Page.for_runtime_exception(context, @ex).to_s
        else
          "<html><body><pre>#{@ex.message}</pre></body></html>"
        end
      end
    end

    include Amber::Controller::Error::Helpers
  end
end
