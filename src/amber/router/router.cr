require "amber_router"

module Amber
  module Router
    # This is the main application handler all routers should finally hit this
    # handler.
    class Router
      property :routes, :routes_hash, :socket_routes
      PATH_EXT_REGEX = /\.[^$\/]+$/

      def initialize
        @routes = RouteSet(Route).new
        @routes_hash = {} of String => Route
        @socket_routes = Array(NamedTuple(path: String, handler: WebSockets::Server::Handler)).new
      end

      def get_socket_handler(request)
        raise Exceptions::RouteNotFound.new(request) unless socket_route_defined?(request)
        @socket_routes.select { |sr| sr[:path] == request.path }.first.[:handler]
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
        @routes.add(route.trail, route)
        @routes_hash["#{route.controller.downcase}##{route.action.to_s.downcase}"] = route
        add_head(route) if route.verb == "GET"
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

      def match_by_controller_action(controller, action)
        @routes_hash["#{controller}##{action}"]
      end

      def match(http_verb, resource) : RoutedResult(Route)
        result = @routes.find build_node(http_verb, resource)
        if result.found?
          result
        else
          @routes.find build_node(http_verb, resource.sub(PATH_EXT_REGEX, ""))
        end
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
