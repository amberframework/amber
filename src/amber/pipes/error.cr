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
        Log.warn(exception: ex) { "Error: 403".colorize(:yellow) }
      rescue ex : Amber::Exceptions::RouteNotFound
        context.response.status_code = 404
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.not_found)
        Log.warn(exception: ex) { "Error: 404".colorize(:yellow) }
      rescue ex : Exception
        context.response.status_code = 500
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.internal_server_error)
        Log.error(exception: ex) { "Error: 500".colorize(:red) }
      end
    end
  end
end
