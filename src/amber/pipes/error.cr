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
        context.response.print Amber::Controller::Error.for_runtime_exception(context, ex).to_s
      rescue ex : Amber::Exceptions::RouteNotFound
        context.response.status_code = 404
        context.response.print Amber::Controller::Error.for_runtime_exception(context, ex).to_s
      rescue ex : Exception
        context.response.status_code = 500
        context.response.print Amber::Controller::Error.for_runtime_exception(context, ex).to_s
      end
    end
  end
end
