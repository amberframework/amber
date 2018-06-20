module Amber
  module Pipe
    # The Error pipe catches RouteNotFound and returns a 404. It responds based
    # on the `Accepts` header as JSON or HTML. It also catches any runtime
    # Exceptions and returns a backtrace in text/html format.
    class Error < Base
      include Amber::Exceptions
      include Amber::Exceptions::Validator

      def call(context : HTTP::Server::Context)
        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?
        call_next(context)
      rescue ex
        error(ex)
      end

      def error(ex : ValidationFailed | InvalidParam)
        context.response.status_code = 400
        action = Amber::Controller::Error.new(context, ex)
        context.response.print(action.bad_request)
      end

      def error(ex : Forbidden)
        context.response.status_code = 403
        action = Amber::Controller::Error.new(context, ex)
        context.response.print(action.forbidden)
      end

      def error(ex : RouteNotFound)
        context.response.status_code = 404
        action = Amber::Controller::Error.new(context, ex)
        context.response.print(action.not_found)
      end

      def error(ex)
        context.response.status_code = 500
        action = Amber::Controller::Error.new(context, ex)
        context.response.print(action.internal_server_error)
      end
    end
  end
end
