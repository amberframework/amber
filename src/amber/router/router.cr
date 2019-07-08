require "amber_router"
require "./scope"

module Amber
  module Router
    # This is the main application handler all routers should finally hit this handler.
    class Router
      PATH_EXT_REGEX = Controller::Helpers::Responders::Content::TYPE_EXT_REGEX
      property :routes, :routes_hash, :socket_routes

      def initialize
        @routes = RouteSet(Route).new
        @routes_hash = {} of String => Route
        @socket_routes = Array(NamedTuple(path: String, handler: WebSockets::Server::Handler)).new
      end

      def get_socket_handler(request) : WebSockets::Server::Handler
        if socket_route = @socket_routes.find { |sr| sr[:path] == request.path }
          socket_route.[:handler]
        else
          raise Exceptions::RouteNotFound.new(request)
        end
      end

      # This registers all the routes for the application
      def draw(valve : Symbol)
        with DSL::Router.new(self, valve, Scope.new) yield
      end

      def draw(valve : Symbol, namespace : String)
        with DSL::Router.new(self, valve, Scope.new([namespace])) yield
      end

      def add(route : Route)
        build_node(route.verb, route.resource)
        @routes.add(route.trail, route, route.constraints)
        @routes_hash["#{route.controller.downcase}##{route.action.to_s.downcase}"] = route
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
        if has_content_ext(resource)
          result = @routes.find build_node(http_verb, resource.sub(PATH_EXT_REGEX, ""))
          return result if result.found?
        end
        @routes.find build_node(http_verb, resource)
      end

      private def build_node(http_verb : Symbol | String, resource : String)
        "#{http_verb.to_s.downcase}#{resource}"
      end

      private def has_content_ext(str)
        str.includes?('.') && str.match PATH_EXT_REGEX
      end
    end
  end
end
