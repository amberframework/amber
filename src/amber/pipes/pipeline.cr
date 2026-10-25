module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol

      def initialize(@valve = :web)
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
        @drain = {} of Symbol => (HTTP::Handler | (HTTP::Server::Context ->))
      end

      def call(context : HTTP::Server::Context)
        websocket = context.websocket?
        track_pending_request = !websocket
        Amber::Jobs::Worker.begin_request if track_pending_request

        raise Amber::Exceptions::RouteNotFound.new(context.request) unless context.valid_route?

        http_route = context.request.matched_route.payload?
        check_request_constraint!(context, http_route)

        if websocket
          context.process_websocket_request
        elsif http_route.nil?
          # A plain HTTP request to a path that only has a socket route.
          raise Amber::Exceptions::RouteNotFound.new(context.request)
        elsif @drain[context.valve]
          @drain[context.valve].call(context)
          context.finalize_response!
        end
      rescue e : Amber::Exceptions::BadRequest
        # Answer directly: routing reads the body to resolve `_method`, so the
        # Error pipe would hit the same error while re-resolving the route.
        respond_to_bad_request(context, e, 400)
      rescue e : Amber::Schema::RequestParseError
        respond_to_bad_request(context, e, e.http_status)
      rescue e : Amber::Exceptions::Base
        Amber::Pipe::Error.new.call(context)
      ensure
        context.request.delete_uploaded_files
        Amber::Jobs::Worker.end_request if track_pending_request
      end

      # A socket-only route has no HTTP route payload, so only an HTTP
      # route's request constraint is checked.
      private def check_request_constraint!(context : HTTP::Server::Context, http_route : Amber::Route?) : Nil
        return unless http_route
        constraint = http_route.request_constraint
        return unless constraint
        return if constraint.matches?(context.request)

        raise Amber::Exceptions::RouteNotFound.new(context.request)
      end

      private def respond_to_bad_request(context : HTTP::Server::Context, error : Exception, status : Int32) : Nil
        context.response.status_code = status
        context.response.print(Amber::Controller::Error.new(context, error).bad_request)
      end

      # Connects pipes to a pipeline to process requests
      def build(valve : Symbol, &)
        @valve = valve
        @pipeline[valve] = [] of HTTP::Handler unless pipeline.has_key? valve
        with DSL::Pipeline.new(self) yield
      end

      def plug(pipe : HTTP::Handler)
        @pipeline[valve] << pipe
      end

      def prepare_pipelines
        pipeline.keys.each do |valve|
          @drain[valve] ||= build_pipeline(pipeline[valve], Amber::Pipe::Controller.new)
        end
      end

      def build_pipeline(pipes, last_pipe : HTTP::Handler | (HTTP::Server::Context ->))
        if pipes.empty?
          last_pipe
        else
          0.upto(pipes.size - 2) { |i| pipes[i].next = pipes[i + 1] }
          pipes.last.next = last_pipe if last_pipe
          pipes.first
        end
      end
    end
  end
end
