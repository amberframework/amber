module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol

      def initialize
        @valve = :web
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
        @drain = {} of Symbol => (HTTP::Handler | (HTTP::Server::Context ->))
      end

      def call(context : HTTP::Server::Context)
        raise Amber::Exceptions::RouteNotFound.new(context.request) if context.invalid_route?

        if context.websocket?
          context.process_websocket_request
        else
          @drain[context.valve].call(context) if @drain[context.valve]
        end
      rescue e : Amber::Exceptions::Base
        e.set_response(context.response)
      end

      # Connects pipes to a pipeline to process requests
      def build(valve : Symbol, &block)
        @valve = valve
        @pipeline[valve] = [] of HTTP::Handler unless pipeline.key? valve
        with DSL::Pipeline.new(self) yield
      end

      def plug(pipe : HTTP::Handler)
        @pipeline[valve] << pipe
      end

      def prepare_pipelines
        pipeline.keys.each do |valve|
          @drain[valve] ||= build_pipeline(
            pipeline[valve],
            ->(context : HTTP::Server::Context) {
              context.response.print(context.process_request)
            })
        end
      end

      def build_pipeline(pipes, last_pipe : (HTTP::Server::Context ->))
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
