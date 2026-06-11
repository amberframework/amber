require "./engine"
require "./scope"
require "./route_info"

module Amber
  module Router
    # This is the main application handler all routers should finally hit this handler.
    class Router
      PATH_EXT_REGEX = Controller::Helpers::Responders::Content::TYPE_EXT_REGEX
      property :routes, :routes_hash, :socket_routes, :scope

      def initialize
        @routes = RouteSet(Route).new
        @routes_hash = {} of String => Route
        @named_routes = {} of Symbol => Route
        @socket_routes = Array(NamedTuple(path: String, handler: WebSockets::Server::Handler)).new
        @scope = Scope.new
      end

      def get_socket_handler(request) : WebSockets::Server::Handler
        if socket_route = @socket_routes.find { |sr| sr[:path] == request.path }
          socket_route.[:handler]
        else
          raise Exceptions::RouteNotFound.new(request)
        end
      end

      # This registers all the routes for the application
      def draw(valve : Symbol, &)
        with DSL::Router.new(self, valve, scope) yield
      end

      def draw(valve : Symbol, namespace : String, &)
        scope.push(namespace)
        with DSL::Router.new(self, valve, scope) yield
        scope.pop
      end

      def add(route : Route)
        build_node(route.verb, route.resource)
        @routes.add(route.trail, route, route.constraints)
        @routes_hash["#{route.controller.downcase}##{route.action.to_s.downcase}"] = route
        if route_name = route.name
          @named_routes[route_name] = route
        end
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

      # Looks up a named route by its symbol name.
      def match_by_name(name : Symbol) : Route?
        @named_routes[name]?
      end

      def match(http_verb, resource) : RoutedResult(Route)
        if has_content_ext(resource)
          result = @routes.find build_node(http_verb, resource.sub(PATH_EXT_REGEX, ""))
          return result if result.found?
        end
        @routes.find build_node(http_verb, resource)
      end

      # Returns all registered routes as RouteInfo structs for introspection.
      def all_routes : Array(RouteInfo)
        collected = [] of RouteInfo
        seen = Set(String).new

        @routes_hash.each do |_key, route|
          path = "#{route.scope}#{route.resource}"
          unique_key = "#{route.verb}:#{path}:#{route.action}"
          next if seen.includes?(unique_key)
          seen.add(unique_key)

          collected << RouteInfo.new(
            verb: route.verb,
            path: path,
            controller: route.controller,
            action: route.action.to_s,
            valve: route.valve.to_s,
            scope: route.scope.to_s,
            name: route.name.try(&.to_s),
            constraints: route.constraints.transform_values(&.to_s)
          )
        end

        collected.sort_by(&.path)
      end

      # Returns a formatted route table string suitable for display.
      def route_table : String
        route_table_for(all_routes)
      end

      # Returns a formatted route table string for a given list of routes.
      def route_table_for(routes : Array(RouteInfo)) : String
        String.build do |io|
          io << "Verb".ljust(8)
          io << "Path".ljust(40)
          io << "Controller#Action".ljust(40)
          io << "Pipe".ljust(10)
          io << "Name".ljust(20)
          io << "\n"
          io << "-" * 118
          io << "\n"
          routes.each do |route|
            io << route.to_s
            io << "\n"
          end
        end
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
