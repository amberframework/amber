module Amber
  module Pipe
    # This class picks the correct pipeline based on the request
    class Pipeline < Base
      SERVER = Amber::Server.instance

      @pipes : Hash(Symbol, Array(HTTP::Handler))

      def self.instance
        @@instance ||= new
      end

      def inialize
        @pipes = {}  of Symbol => Array(HTTP::Handler)
      end

      # Connects pipes to a pipeline to process requests
      def pipe_through(valve : Symbol)
        yield valve
      end

      def pipes(pipe : HTTP::Handler)
        @pipelines[valve] << pipe
      end

    end
  end
end