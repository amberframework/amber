require "./base"

module Amber::Controller
  class Error < Base
    alias AmberException = Amber::Exceptions::Forbidden | Amber::Exceptions::RouteNotFound | Exception

    def initialize(@context : HTTP::Server::Context, @ex : AmberException)
      super(@context)
    end

    def not_found
      if context.request.headers["Accept"]?
        content_type = context.request.headers["Accept"].split(",")[0]
      else
        content_type = "text/plain"
      end
      context.response.content_type = content_type
      message_based_on_content_type(@ex.message, content_type)
    end

    def internal_server_error
      context.response.content_type = "text/plain"
      "ERROR: #{@ex.inspect_with_backtrace}"
    end

    def forbidden
      if context.request.headers["Accept"]?
        content_type = context.request.headers["Accept"].split(",")[0]
      else
        content_type = "text/plain"
      end
      context.response.content_type = content_type
      message_based_on_content_type(@ex.message, content_type)
    end

    private def message_based_on_content_type(message, content_type)
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
