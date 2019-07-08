module Amber::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Amber::Router::Router, valve : Symbol, scope : Amber::Router::Scope do
    RESOURCES = [:get, :post, :put, :patch, :delete, :options, :head, :trace, :connect]

    macro route(verb, resource, controller, action, constraints = {} of String => Regex)
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
        %verb, {{resource}}, %handler, {{action}}, valve, scope, "{{controller.id}}", {{constraints}}
      )

      router.add(%route)
    end

    macro namespace(scoped_namespace)
      scope.push({{scoped_namespace}})
      {{yield}}
    end

    {% for verb in RESOURCES %}
      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
        {% if verb == :get %}
        route :head, \{{*args}}
        {% end %}
        {% if ![:trace, :connect, :options, :head].includes? verb %}
        route :options, \{{*args}}
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
