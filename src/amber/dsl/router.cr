require "./schema_router"

module Amber::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  # For now, always use the regular Router to maintain compatibility
  # SchemaRouter can be used explicitly when needed
  class Router
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
    end

    macro namespace(scoped_namespace)
      scope.push({{scoped_namespace}})
      {{yield}}
      scope.pop
    end

    # Scopes all routes defined in the block to require the given constraint.
    # The constraint object must implement Amber::Router::Constraint.
    def constraint(constraint_object : Amber::Router::Constraint, &)
      previous_constraint = @_active_constraint
      @_active_constraint = constraint_object
      with self yield
      @_active_constraint = previous_constraint
    end

    # API versioning macro - URL-based strategy uses namespace,
    # header-based and media-type-based strategies use constraints.
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
