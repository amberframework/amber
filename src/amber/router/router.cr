require "radix"

module Amber
  module Router
    # This is the main application handler all routers should finally hit this
    # handler.
    class Router
      property :routes, :routes_hash, :socket_routes
      PATH_EXT_REGEX = /\.[^$\/]+$/

      def initialize
        @routes = Radix::Tree(Route).new
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
        node = @routes.add(route.trail, route)
        @routes_hash["#{route.controller.downcase}##{route.action.to_s.downcase}"] = route
        add_head(route) if route.verb == "GET"
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

      def match_by_controller_action(controller, action)
        @routes_hash["#{controller}##{action}"]
      end

      def all
        root_node = @routes.root
        all_routes = {} of String => String
        all_routes[root_node.payload.verb + root_node.payload.resource] = root_node.payload.to_json
        add_children(root_node, all_routes)
        all_routes
      end

      def add_children(node, accumulator = {} of String => String)
        node.children.each do |c|
          if c.payload?
            accumulator[c.payload.verb + c.payload.resource] = c.payload.to_json
          end
          add_children(c, accumulator)
        end
      end

      def match(http_verb, resource) : Radix::Result(Amber::Route)
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
