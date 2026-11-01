module Amber
  module Pipe
    # The Error pipe catches RouteNotFound and returns a 404. It responds based
    # on the `Accepts` header as JSON or HTML. It also catches any runtime
    # Exceptions and returns a backtrace in text/html format.
    class Error < Base
      Log = ::Log.for("error")

      def call(context : HTTP::Server::Context)
        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?
        call_next(context)
      rescue ex : Amber::Exceptions::Forbidden
        context.response.status_code = 403
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.forbidden)
        Log.warn(exception: ex) { error_msg(context, 403).colorize(:yellow) }
      rescue ex : Amber::Exceptions::BadRequest
        context.response.status_code = 400
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.bad_request)
        Log.warn { error_msg(context, 400).colorize(:yellow) }
      rescue ex : Amber::Schema::RequestParseError
        # A request body that could not be decoded, such as one beyond a
        # limit, read by an action through the schema parsers directly.
        context.response.status_code = ex.http_status
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.bad_request)
        Log.warn { error_msg(context, ex.http_status).colorize(:yellow) }
      rescue ex : Amber::Exceptions::RouteNotFound
        context.response.status_code = 404
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.not_found)
        Log.warn(exception: ex) { error_msg(context, 404).colorize(:yellow) }
      rescue ex : Exception
        context.response.status_code = 500
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.internal_server_error)
        Log.error(exception: ex) { error_msg(context, 500).colorize(:red) }
      end

      private def error_msg(context : HTTP::Server::Context, number : Int)
        request = context.request
        "Error #{number} - #{request.method} #{request.path}"
      end
    end
  end
end
