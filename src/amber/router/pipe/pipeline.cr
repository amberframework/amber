module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    # and executes it.
    class Pipeline < Base
      getter pipeline
      getter valve : Symbol

      def self.instance
        @@instance ||= new
      end

      def initialize
        @valve = :web
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
        @drain = {} of Symbol => HTTP::Handler
      end

      def call(context : HTTP::Server::Context)
        raise Exceptions::RouteNotFound.new(context.request) if context.invalid_route?

        if context.websocket?
          context.process_websocket_request
        else
          @drain[context.valve].call(context) if @drain[context.valve]
        end

        context
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

      def build_pipeline(pipes, last_pipe : (HTTP::Server::Context ->)? = nil)
        raise ArgumentError.new "You must specify at least one HTTP Handler." if pipes.empty?
        0.upto(pipes.size - 2) { |i| pipes[i].next = pipes[i + 1] }
        pipes.last.next = last_pipe if last_pipe
        pipes.first
      end
    end
  end
end
