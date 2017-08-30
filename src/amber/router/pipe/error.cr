module Amber
  module Pipe
    # The Error Handler catches RouteNotFound and returns a 404.  It will
    # response based on the `Accepts` header as JSON or HTML.  It also catches
    # any runtime Exceptions and returns a backtrace in text/plain format.
    class Error < Base
      def call(context : HTTP::Server::Context)
        begin
          call_next(context)
        rescue ex : Amber::Exceptions::Forbidden
          context.response.status_code = 403
          if context.request.headers["Accept"]?
            content_type = context.request.headers["Accept"].split(",")[0]
          else
            content_type = "text/plain"
          end
          context.response.content_type = content_type
          message = message_based_on_content_type(ex.message, content_type)
          context.response.print(message)
        rescue ex : Amber::Exceptions::RouteNotFound
          context.response.status_code = 404
          if context.request.headers["Accept"]?
            content_type = context.request.headers["Accept"].split(",")[0]
          else
            content_type = "text/plain"
          end
          context.response.content_type = content_type
          message = message_based_on_content_type(ex.message, content_type)
          context.response.print(message)
        rescue ex : Exception
          context.response.status_code = 500
          context.response.content_type = "text/plain"
          context.response.print("ERROR: ")
          ex.inspect_with_backtrace(context.response)
        end
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
end
