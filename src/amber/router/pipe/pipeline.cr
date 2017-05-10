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
        @router = Pipe::Router.instance
        @valve = :web
        @pipeline = {} of Symbol => Array(HTTP::Handler)
        @pipeline[@valve] = [] of HTTP::Handler
      end

      def call(context : HTTP::Server::Context)
        if context.request.headers["Upgrade"]? == "websocket"
          @router.get_socket_handler(context.request).call(context)
        else
          valve = @router.match_by_request(context.request).payload.valve
          pipe = proccess_pipeline(@pipeline[valve])
          pipe.call(context)
          context
        end
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

      def proccess_pipeline(pipes, last_pipe : (Context ->)? = nil)
        pipes << Router.instance unless pipes.includes? Router.instance
        raise ArgumentError.new "You must specify at least one pipeline." if pipes.empty?
        0.upto(pipes.size - 2) { |i| pipes[i].next = pipes[i + 1] }
        pipes.last.next = last_pipe if last_pipe
        pipes.first
      end
    end
  end
end
