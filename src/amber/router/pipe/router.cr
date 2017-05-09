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
        @socket_routes = Array(NamedTuple(path: String, handler: WebSockets::Server::Handler)).new
      end

      def call(context : HTTP::Server::Context)
        raise Exceptions::RouteNotFound.new(context.request) if !route_defined?(context.request)
        route_node = match_by_request(context.request)
        merge_params(route_node.params, context)
        content = route_node.payload.call(context)
      ensure
        context.response.print(content)
        context
      end

      def get_socket_handler(request)
        raise Exceptions::RouteNotFound.new(request) if !socket_route_defined?(request)
        @socket_routes.select{|sr| sr[:path] == request.path }.first.[:handler]
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

      def add_socket_route(route, handler : WebSockets::Server::Handler)
        @socket_routes.push({path: route, handler: handler})
      end

      def route_defined?(request)
        match_by_request(request).found?
      end

      def socket_route_defined?(request)
        @socket_routes.map(&.[:path]).includes?(request.path)
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
        @routes.add(route.trail_head, route)
      end
    end
  end
end
