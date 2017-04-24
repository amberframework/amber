require "radix"

module Amber
  module Pipe
    class Router < Base
      property :routes

      def self.instance
        @@instance ||= new
      end

      def initialize
        @routes = Radix::Tree(Route).new
      end

      def call(context : HTTP::Server::Context)
        raise Exceptions::RouteNotFound.new(context.request) if !route_defined?(context.request)
        route_node = match_by_request(context.request)
        merge_params(route_node.params, context)
        route_node.payload.controller.set_context(context)
        content = route_node.payload.handler.call
      ensure
        context.response.print(content)
        context
      end

      # This registers all the routes for the application
      def draw
        with Support::DSL::Router.new(self) yield
      end

      def add(route : Route)
        trail = build_node(route.verb, route.resource)
        node = @routes.add(trail, route)
        add_head(route) if route.verb == :GET
        node
      rescue Radix::Tree::DuplicateError
        raise Amber::Exceptions::DuplicateRouteError.new(route)
      end

      def route_defined?(request)
        match_by_request(request).found?
      end

      def match_by_request(request)
        match(request.method, request.path)
      end

      private def merge_params(params, context)
        params.each { |k, v| context.params.add(k.to_s, v) }
      end

      private def match(http_verb, resource) : Radix::Result(Amber::Route)
        @routes.find build_node(http_verb, resource)
      end

      private def build_node(http_verb : Symbol | String, resource : String)
        "#{http_verb.to_s.downcase}#{resource}"
      end

      private def add_head(route)
        trail = build_node(:HEAD, route.resource)
        @routes.add(trail, route)
      end
    end
  end
end
