module Amber
  module Pipe
    # The Error pipe catches RouteNotFound and returns a 404. It responds based
    # on the `Accepts` header as JSON or HTML. It also catches any runtime
    # Exceptions and returns a backtrace in text/html format.
    class Error < Base
      def call(context : HTTP::Server::Context)
        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?
        call_next(context)
      rescue ex : Amber::Exceptions::Forbidden
        context.response.status_code = 403
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.forbidden)
        Amber.logger.warn error.forbidden, "Error: 403", :yellow
      rescue ex : Amber::Exceptions::RouteNotFound
        context.response.status_code = 404
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.not_found)
        Amber.logger.warn error.not_found, "Error: 404", :yellow
      rescue ex : Exception
        context.response.status_code = 500
        error = Amber::Controller::Error.new(context, ex)
        context.response.print(error.internal_server_error)
        Amber.logger.error error.internal_server_error, "Error: 500", :red
      end
    end
  end
end
