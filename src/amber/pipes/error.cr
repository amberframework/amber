module Amber
  module Pipe
    # The Error pipe catches RouteNotFound and returns a 404. It responds based
    # on the `Accepts` header as JSON or HTML. It also catches any runtime
    # Exceptions and returns a backtrace in text/html format.
    class Error < Base
      Log = ::Log.for("error")

      # Renders the error page for an exception raised further down the
      # pipeline. An exception raised after the response's status line and
      # headers went to the client is raised again instead: the page can no
      # longer replace them, and the HTTP server logs it and closes the
      # connection.
      def call(context : HTTP::Server::Context)
        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?
        call_next(context)
      rescue ex : Exception
        raise ex if context.response.headers_sent?

        render_error_page(context, ex)
      end

      private def render_error_page(context : HTTP::Server::Context, exception : Exception) : Nil
        error = Amber::Controller::Error.new(context, exception)
        if exception.is_a?(Amber::Exceptions::Forbidden)
          context.response.status_code = 403
          context.response.print(error.forbidden)
          Log.warn(exception: exception) { paint(error_msg(context, 403), :yellow) }
        elsif exception.is_a?(Amber::Exceptions::BadRequest)
          context.response.status_code = 400
          context.response.print(error.bad_request)
          Log.warn { paint(error_msg(context, 400), :yellow) }
        elsif exception.is_a?(Amber::Schema::RequestParseError)
          # A request body that could not be decoded, such as one beyond a
          # limit, read by an action through the schema parsers directly.
          context.response.status_code = exception.http_status
          context.response.print(error.bad_request)
          Log.warn { paint(error_msg(context, exception.http_status), :yellow) }
        elsif exception.is_a?(Amber::Exceptions::RouteNotFound)
          context.response.status_code = 404
          context.response.print(error.not_found)
          Log.warn(exception: exception) { paint(error_msg(context, 404), :yellow) }
        else
          context.response.status_code = 500
          context.response.print(error.internal_server_error)
          Log.error(exception: exception) { paint(error_msg(context, 500), :red) }
        end
      end

      private def paint(message : String, color : Symbol)
        Support::LogColor.paint(message, color, Amber.settings.logging.colorize)
      end

      private def error_msg(context : HTTP::Server::Context, number : Int)
        request = context.request
        "Error #{number} - #{request.method} #{request.path}"
      end
    end
  end
end
