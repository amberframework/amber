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
        valve = @router.match_by_request(context.request).payload.valve
        pipe = proccess_pipeline(@pipeline[valve])
        pipe.call(context)
        context
      end

      # Connects pipes to a pipeline to process requests
      def build(valve : Symbol, &block)
        @valve = valve
        @pipeline[@valve] = [Router.instance] of HTTP::Handler unless @pipeline.key? @valve
        with self yield
      end

      def plug(pipe : HTTP::Handler)
        @pipeline[@valve].unshift(pipe)
      end

      def proccess_pipeline(pipeline, last_pipe : (Context ->)? = nil)
        raise ArgumentError.new "You must specify at least one pipeline." if pipeline.empty?
        0.upto(pipeline.size - 2) { |i| pipeline[i].next = pipeline[i + 1] }
        pipeline.last.next = last_pipe if last_pipe
        pipeline.first
      end
    end
  end
end
