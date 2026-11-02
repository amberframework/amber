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

        if websocket
          # A socket declared in a `constraint` block is held to that block,
          # through the socket route lookup. A socket declared outside any is
          # held to the constraint of an HTTP route on the same path.
          socket_handler = context.request.process_websocket
          if Amber::Server.router.socket_route_constraint(socket_handler).nil?
            check_request_constraint!(context, http_route)
          end

          # The handshake goes straight to the socket handler, past every
          # pipeline's pipes, whether or not an HTTP route also matches its path.
          write_application_security_headers(context)
          context.process_websocket_request(socket_handler)
        elsif http_route.nil?
          # A plain HTTP request to a path that only has a socket route.
          raise Amber::Exceptions::RouteNotFound.new(context.request)
        else
          check_request_constraint!(context, http_route)
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
        # Once the status line and headers have gone out, no error page can
        # replace them; the HTTP server logs the error and closes the connection.
        raise e if context.response.headers_sent?

        # A request rejected here (no route, a failed route constraint, or a
        # socket-only path without an upgrade) never reached a pipeline's
        # pipes, so its error page gets its security headers here.
        write_security_headers_outside_pipeline(context)
        render_error_page(context, e)
      ensure
        # This handler is the outermost HTTP::Handler (Amber::Server passes it
        # straight to HTTP::Server.new), so it sees every request finish,
        # success or error. Upload tempfiles and the multipart body copy are
        # deleted here, unless the action kept an upload with
        # `Amber::Router::File#move_to` or `#retain!`.
        context.request.delete_uploaded_files
        Amber::Jobs::Worker.end_request if track_pending_request
      end

      # A socket-only route has no HTTP route payload, so only an HTTP
      # route's request constraint is checked.
      private def check_request_constraint!(context : HTTP::Server::Context, http_route : Amber::Route?) : Nil
        return unless http_route
        constraint = http_route.request_constraint
        return unless constraint
        return if context.request.request_constraint_accepted?(context.request.matched_route)
        return if constraint.matches?(context.request)

        raise Amber::Exceptions::RouteNotFound.new(context.request)
      end

      # Routing failed before any pipeline was chosen, so the application-wide
      # security headers apply; the route is not looked up again here.
      private def respond_to_bad_request(context : HTTP::Server::Context, error : Exception, status : Int32) : Nil
        raise error if context.response.headers_sent?

        write_application_security_headers(context)
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

      # Renders *exception* through `Amber::Pipe::Error`, so the error page
      # answers the exception that was raised: a failed route constraint gets
      # the same 404 page, with the headers already written, as a request
      # that matched no route.
      private def render_error_page(context : HTTP::Server::Context, exception : Amber::Exceptions::Base) : Nil
        error_pipe = Amber::Pipe::Error.new
        error_pipe.next = ->(_context : HTTP::Server::Context) : Nil { raise exception }
        error_pipe.call(context)
      end

      # Writes security headers for an error response that no pipeline's
      # pipes produce. A request whose route matched but whose constraint
      # failed gets the `SecurityHeaders` pipe plugged into that route's
      # pipeline, and nothing when that pipeline plugs none. A WebSocket
      # handshake and a request with no route belong to no pipeline: they
      # get the application-wide settings (see
      # `write_application_security_headers`).
      private def write_security_headers_outside_pipeline(context : HTTP::Server::Context) : Nil
        matched_route = context.request.matched_route.payload?
        if matched_route && !context.websocket?
          if security_headers = plugged_security_headers(matched_route.valve)
            security_headers.write_headers(context)
          end
        else
          write_application_security_headers(context)
        end
      end

      # Writes the application-wide `security_headers` settings when the
      # application plugs `SecurityHeaders` into any pipeline. A header
      # already on the response is kept.
      private def write_application_security_headers(context : HTTP::Server::Context) : Nil
        SecurityHeaders.new.write_headers(context) if plugs_security_headers?
      end

      # Returns the `SecurityHeaders` pipe plugged into the pipeline for
      # *valve*, or `nil` when that pipeline plugs none.
      private def plugged_security_headers(valve : Symbol) : SecurityHeaders?
        list_of_pipes = pipeline[valve]?
        return unless list_of_pipes

        list_of_pipes.each do |pipe|
          return pipe if pipe.is_a?(SecurityHeaders)
        end
        nil
      end

      # Returns `true` when any pipeline plugs a `SecurityHeaders` pipe.
      private def plugs_security_headers? : Bool
        pipeline.each_key.any? { |valve| !plugged_security_headers(valve).nil? }
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
