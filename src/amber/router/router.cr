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
        @extension_routes_drawn = false
        @socket_routes = Array(NamedTuple(path: String, handler: WebSockets::Server::Handler)).new
        @socket_route_constraints = {} of WebSockets::Server::Handler => Constraint
        @scope = Scope.new
      end

      # Returns the handler of the first socket route whose path is
      # *request*'s and whose constraint, if it was declared in a
      # `constraint` block, *request* meets. Raises
      # `Exceptions::RouteNotFound` when there is none.
      def get_socket_handler(request) : WebSockets::Server::Handler
        socket_route = @socket_routes.find do |candidate_route|
          next false unless candidate_route[:path] == request.path

          constraint = @socket_route_constraints[candidate_route[:handler]]?
          constraint.nil? || constraint.matches?(request)
        end
        raise Exceptions::RouteNotFound.new(request) unless socket_route

        socket_route[:handler]
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
        @extension_routes_drawn ||= spells_extension?(route.trail)
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

      # Holds the socket route served by *handler* to *constraint*, the
      # `constraint` block its `websocket` line sits in.
      def constrain_socket_route(handler : WebSockets::Server::Handler, constraint : Constraint) : Nil
        @socket_route_constraints[handler] = constraint
      end

      # Returns the constraint the socket route served by *handler* was
      # declared under, or `nil` when it was declared outside any.
      def socket_route_constraint(handler : WebSockets::Server::Handler) : Constraint?
        @socket_route_constraints[handler]?
      end

      def socket_route_defined?(request)
        @socket_routes.map(&.[:path]).includes?(request.path)
      end

      def match_by_request(request)
        match(request.method, request.path, request)
      end

      def match_by_controller_action(controller, action)
        @routes_hash["#{controller}##{action}"]
      end

      # Looks up a named route by its symbol name.
      def match_by_name(name : Symbol) : Route?
        @named_routes[name]?
      end

      # Matches a request path to a route. Within one lookup, routes compete in
      # the order they were drawn. A path that ends in a known response
      # extension may take two lookups, and the first that qualifies wins, so a
      # later `get "/overview.md"` answers `/overview.md` ahead of an earlier
      # `get "/overview"`.
      #
      # A path ending in a known response extension (`.json`, `.md`, ...) is
      # matched in this order:
      #
      # 1. the full path, when the route it reaches spells the extension as
      #    the fixed end of its own path (`get "/overview.md"`,
      #    `get "/overview(.md)"`) and that route's request constraint, if
      #    any, accepts `request`;
      # 2. the path without the extension (`/users/1.json` matches
      #    `/users/:id`, and the controller responds in that format);
      # 3. the full path as written.
      #
      # Step 1 runs only when some drawn route spells a known extension, so an
      # app without one matches exactly as before. A declared route whose
      # request constraint rejected `request` in step 1 is not offered again,
      # neither in step 3 nor in step 2 through another expansion of the same
      # route (`get "/notes(.md)"` also matches `/notes`). A different route
      # that matches the path without the extension still answers; when none
      # does, the path is not found.
      def match(http_verb, resource, request : HTTP::Request? = nil) : RoutedResult(Route)
        extension = content_ext(resource)
        return find_route(http_verb, resource) unless extension

        rejected_route : Route? = nil
        if @extension_routes_drawn
          literal = find_route(http_verb, resource)
          if declares_extension?(literal, extension)
            return literal if constraint_accepts?(literal, request)
            rejected_route = literal.payload?
          end
        end

        stripped = find_route(http_verb, resource.byte_slice(0, resource.bytesize - extension.bytesize))
        if rejected_route
          return stripped if stripped.found? && !same_registration?(stripped.payload?, rejected_route)
          return RoutedResult(Route).new(nil)
        end
        return stripped if stripped.found?

        literal || find_route(http_verb, resource)
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

      private def find_route(http_verb : Symbol | String, resource : String) : RoutedResult(Route)
        {% if flag?(:amber_router_legacy_match) %}
          @routes.find(build_node(http_verb, resource))
        {% elsif flag?(:amber_router_best_match) %}
          @routes.find_best(normalize_http_verb(http_verb), resource)
        {% else %}
          @routes.find_span(normalize_http_verb(http_verb), resource)
        {% end %}
      end

      private def normalize_http_verb(http_verb : Symbol) : String
        case http_verb
        when :GET, :get       then "get"
        when :POST, :post     then "post"
        when :PUT, :put       then "put"
        when :PATCH, :patch   then "patch"
        when :DELETE, :delete then "delete"
        when :HEAD, :head     then "head"
        when :OPTIONS, :options
          "options"
        else
          http_verb.to_s.downcase
        end
      end

      private def normalize_http_verb(http_verb : String) : String
        case http_verb
        when "GET", "get"         then "get"
        when "POST", "post"       then "post"
        when "PUT", "put"         then "put"
        when "PATCH", "patch"     then "patch"
        when "DELETE", "delete"   then "delete"
        when "HEAD", "head"       then "head"
        when "OPTIONS", "options" then "options"
        else                           http_verb.downcase
        end
      end

      # Returns the known response extension at the end of `path`, dot
      # included (`".md"`), or `nil`.
      private def content_ext(path : String) : String?
        return unless path.includes?('.')
        path.match(PATH_EXT_REGEX).try(&.[0])
      end

      # True when the matched pattern (verb, scope and resource, with optional
      # parts already expanded) ends in a fixed segment that spells
      # `extension`. A variable segment such as `:slug.md` spells nothing.
      private def declares_extension?(result : RoutedResult(Route), extension : String) : Bool
        return false unless result.found?
        last_segment = result.path.rpartition('/').last
        return false if last_segment.starts_with?(':') || last_segment.starts_with?('*')
        last_segment.ends_with?(extension)
      end

      # A constraint that reads `request.params` sees the candidate's route
      # parameters, because the candidate stands as the request's matched route
      # while the constraint runs. An accepted check is recorded on the request
      # against this exact result, so the pipeline skips its own check only when
      # this result became the request's matched route.
      # Whether two matches came from one drawn route: the same verb, scope and
      # resource as written, and the same controller action. The optional
      # expansions of one route share all of these.
      private def same_registration?(candidate : Route?, drawn : Route) : Bool
        return false unless candidate
        candidate.trail == drawn.trail &&
          candidate.controller == drawn.controller &&
          candidate.action == drawn.action
      end

      private def constraint_accepts?(result : RoutedResult(Route), request : HTTP::Request?) : Bool
        constraint = result.payload?.try(&.request_constraint)
        return true unless constraint && request
        accepted = request.matching_candidate(result) { constraint.matches?(request) }
        request.request_constraint_accepted!(result) if accepted
        accepted
      end

      # A conservative test made once per drawn route: whether any fixed
      # segment of its path, optional parentheses removed, ends in a known
      # extension. It is true for every route that can spell an extension at
      # its end, and for some that cannot (`/notes.md/:id`), which only costs
      # those apps the extra full-path lookup.
      private def spells_extension?(trail : String) : Bool
        trail.delete("()").split('/').any? do |segment|
          next false if segment.starts_with?(':') || segment.starts_with?('*')
          PATH_EXT_REGEX.matches?(segment)
        end
      end
    end
  end
end
