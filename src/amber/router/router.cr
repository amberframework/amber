require "radix"

module Amber
  module Router
    # This is the main application handler all routers should finally hit this
    # handler.
    class Router
      property :routes

      def self.instance
        @@instance ||= new
      end

      def initialize
        @routes = Radix::Tree(Route).new
      end

      # This registers all the routes for the application
      def draw(valve : Symbol)
        with DSL::Router.new(self, valve, "") yield
      end

      def draw(valve : Symbol, scope : String)
        with DSL::Router.new(self, valve, scope) yield
      end

      def add(route : Route)
        trail = build_node(route.verb, route.resource)
        node = @routes.add(route.trail, route)
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

      def match(http_verb, resource) : Radix::Result(Amber::Route)
        @routes.find build_node(http_verb, resource)
      end

      private def build_node(http_verb : Symbol | String, resource : String)
        "#{http_verb.to_s.downcase}#{resource}"
      end

      private def add_head(route)
        @routes.add(route.trail_head, route)
      end
    end
  end
end
