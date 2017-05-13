module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol
      getter router

      def self.instance
        @@instance ||= new
      end

      def initialize
        @router = Router::Router.instance
        @valve = :web
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
      end

      def call(context : HTTP::Server::Context)
        raise Exceptions::RouteNotFound.new(context.request) if validate_route(context)
        route = context.route.payload
        pipe = proccess_pipeline(@pipeline[route.valve], ->(context : HTTP::Server::Context) { context })
        pipe.call(context) if pipe
        context.response.print(route.call(context))
        context
      end

      def validate_route(context)
        !router.route_defined?(context.request)
      end

      # Connects pipes to a pipeline to process requests
      def build(valve : Symbol, &block)
        @valve = valve
        @pipeline[@valve] = [] of HTTP::Handler unless @pipeline.key? @valve
        with DSL::Pipeline.new(self) yield
      end

      def plug(pipe : HTTP::Handler)
        @pipeline[@valve] << pipe
      end

      def proccess_pipeline(pipes, last_pipe : (HTTP::Server::Context ->)? = nil)
        if pipes.any?
          0.upto(pipes.size - 2) { |i| pipes[i].next = pipes[i + 1] }
          pipes.last.next = last_pipe if last_pipe
          pipes.first
        elsif last_pipe
          last_pipe
        end
      end
    end
  end
end
