# Extension to Router DSL to support Schema annotations
module Amber::DSL
  # Extended Router that processes Schema annotations
  # This is identical to the regular Router but adds Schema annotation processing
  class SchemaRouter
    getter router : Amber::Router::Router
    getter valve : Symbol
    getter scope : Amber::Router::Scope
    @_active_constraint : Amber::Router::Constraint? = nil

    def initialize(@router, @valve, @scope)
    end

    def active_constraint : Amber::Router::Constraint?
      @_active_constraint
    end

    RESOURCES = [:get, :post, :put, :patch, :delete, :options, :head, :trace, :connect]

    # Enhanced route macro that works exactly like the regular router
    # Schema annotation processing happens inside the controller
    macro route(verb, resource, controller, action, constraints = {} of String => Regex, route_name = nil)
      %handler = ->(context : HTTP::Server::Context){
        controller = {{controller.id}}.new(context)
        controller.run_before_filter({{action}}) unless context.content
        unless context.content
          context.content = controller.{{ action.id }}.to_s
          controller.run_after_filter({{action}})
        end
      }
      %verb = {{verb.upcase.id.stringify}}
      %route = Amber::Route.new(
        %verb, {{resource}}, %handler, {{action}}, valve, scope, "{{controller.id}}", {{constraints}},
        {% if route_name %}{{route_name}}{% else %}nil{% end %},
        active_constraint
      )

      router.add(%route)

      # Store route metadata for OpenAPI generation
      store_route_metadata({{controller.id.stringify}}, {{action.id.stringify}}, %verb, {{resource}})
    end

    # Store route metadata for OpenAPI documentation generation
    private def store_route_metadata(controller_name : String, action_name : String, verb : String, path : String)
      # This will be used by OpenAPI generator
      Amber::Schema::RouteRegistry.add_route({
        controller: controller_name,
        action:     action_name,
        verb:       verb,
        path:       path,
      })
    end

    macro namespace(scoped_namespace)
      scope.push({{scoped_namespace}})
      {{yield}}
      scope.pop
    end

    # Scopes all routes defined in the block to require the given constraint.
    def constraint(constraint_object : Amber::Router::Constraint, &)
      previous_constraint = @_active_constraint
      @_active_constraint = constraint_object
      with self yield
      @_active_constraint = previous_constraint
    end

    # API versioning macro
    macro api_version(version, strategy = :url, prefix = "", header = "Api-Version", media_type = "application/vnd.amber")
      {% if strategy == :url %}
        namespace "{{prefix.id}}/{{version.id}}" do
          {{yield}}
        end
      {% elsif strategy == :header %}
        constraint(Amber::Router::Constraints::Header.new({{header}}, {{version}})) do
          {{yield}}
        end
      {% elsif strategy == :media_type %}
        constraint(Amber::Router::Constraints::Accept.new({{media_type}}, {{version}})) do
          {{yield}}
        end
      {% end %}
    end

    {% for verb in RESOURCES %}
      macro {{verb.id}}(resource, controller, action, constraints = {} of String => Regex, route_name = nil)
        route {{verb}}, \{{resource}}, \{{controller}}, \{{action}}, \{{constraints}}, \{{route_name}}
        {% if verb == :get %}
        route :head, \{{resource}}, \{{controller}}, \{{action}}, \{{constraints}}
        {% end %}
        {% if ![:trace, :connect, :options, :head].includes? verb %}
        route :options, \{{resource}}, \{{controller}}, \{{action}}, \{{constraints}}
        {% end %}
      end
    {% end %}

    macro resources(resource, controller, only = nil, except = nil, constraints = {} of String => Regex)
      {% actions = [:index, :new, :create, :show, :edit, :update, :destroy] %}

      {% if only %}
        {% actions = only %}
      {% elsif except %}
        {% actions = actions.reject { |i| except.includes? i } %}
      {% end %}

      {% for action in actions %}
        define_action({{resource}}, {{controller}}, {{action}}, {{constraints}})
      {% end %}
    end

    private macro define_action(path, controller, action, constraints = {} of String => Regex)
      {% if action == :index %}
        get "/{{path.id}}", {{controller}}, :index, {{constraints}}
      {% elsif action == :show %}
        get "/{{path.id}}/:id", {{controller}}, :show, {{constraints}}
      {% elsif action == :new %}
        get "/{{path.id}}/new", {{controller}}, :new, {{constraints}}
      {% elsif action == :edit %}
        get "/{{path.id}}/:id/edit", {{controller}}, :edit, {{constraints}}
      {% elsif action == :create %}
        post "/{{path.id}}", {{controller}}, :create, {{constraints}}
      {% elsif action == :update %}
        put "/{{path.id}}/:id", {{controller}}, :update, {{constraints}}
        patch "/{{path.id}}/:id", {{controller}}, :update, {{constraints}}
      {% elsif action == :destroy %}
        delete "/{{path.id}}/:id", {{controller}}, :destroy, {{constraints}}
      {% else %}
        {% raise "Invalid route action '#{action}'" %}
      {% end %}
    end

    def websocket(path, app_socket)
      Amber::WebSockets::Server.create_endpoint(path, app_socket)
    end
  end
end

# Route registry for storing metadata
module Amber::Schema
  class RouteRegistry
    class_property routes = [] of NamedTuple(controller: String, action: String, verb: String, path: String)

    def self.add_route(route_info)
      @@routes << route_info unless @@routes.includes?(route_info)
    end

    def self.clear
      @@routes.clear
    end

    def self.all
      @@routes
    end

    def self.find_by_controller(controller_name : String)
      @@routes.select { |r| r[:controller] == controller_name }
    end

    def self.find_by_action(controller_name : String, action_name : String)
      @@routes.find { |r| r[:controller] == controller_name && r[:action] == action_name }
    end
  end
end
