require "./base"

module Amber::Controller
  class Error < Base
    alias AmberException = Amber::Exceptions::Forbidden | Amber::Exceptions::RouteNotFound | Exception

    def initialize(@context : HTTP::Server::Context, @ex : AmberException)
      super(@context)
      @context.response.content_type = content_type
    end

    def not_found
      response_format(@ex.message)
    end

    def internal_server_error
      context.response.content_type = "text/plain"
      "ERROR: #{@ex.inspect_with_backtrace}"
    end

    def forbidden
      response_format(@ex.message)
    end

    private def content_type
      if context.request.headers["Accept"]?
        request.headers["Accept"].split(",").first
      else
        "text/plain"
      end
    end

    private def response_format(message)
      case content_type
      when "application/json"
        {"error": message}.to_json
      when "text/html"
        "<html><body>#{message}</body></html>"
      else
        message
      end
    end
  end
end
