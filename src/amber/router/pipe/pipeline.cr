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
        Amber::Pipe::Params.instance.call(context)
        if (method = context.params["_method"]?) && %w(patch put delete).includes?(method)
          context.request.method = method  
        end
        route_node = @router.match_by_request(context.request)
        route_node.params.each { |k, v| context.params.add(k.to_s, v) }
        valve = route_node.payload.valve
        pipe = proccess_pipeline(@pipeline[valve], -> (context : HTTP::Server::Context){context})
        pipe.call(context) if pipe
        context.response.print(route_node.payload.call(context))
        context
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
