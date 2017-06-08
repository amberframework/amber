module Amber::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Amber::Router::Router, valve : Symbol, scope : String do
    RESOURCES = [:get, :post, :put, :patch, :delete, :options, :head, :trace, :connect]

    macro route(verb, resource, controller, action)
      %handler = ->(context : HTTP::Server::Context, action : Symbol){
        controller = {{controller.id}}.new(context)
        controller.run_before_filter(:all)
        controller.run_before_filter(action)
        content = controller.{{ action.id }}
        controller.run_after_filter(action)
        controller.run_after_filter(:all)
        content
      }
      %verb = {{verb.upcase.id.stringify}}
      %route = Amber::Route.new(%verb, {{resource}}, %handler, {{action}}, valve, scope, "{{controller.id}}")

      router.add(%route)
    end

    {% for verb in RESOURCES %}
      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
      end
    {% end %}

    macro resources(resource, controller, only = nil, except = nil)
      {% actions = [:index, :new, :create, :show, :edit, :update, :destroy] %}

      {% if only %}
        {% actions = only %}
      {% elsif except %}
        {% actions = actions.reject { |i| except.includes? i } %}
      {% end %}

      {% for action in actions %}
        define_action({{resource}}, {{controller}}, {{action}})
      {% end %}
    end

    macro define_action(path, controller, action)
      {% if action == :index %}
        get "{{path.id}}", {{controller}}, :index
      {% elsif action == :show %}
        get "{{path.id}}/:id", {{controller}}, :show
      {% elsif action == :new %}
        get "{{path.id}}/new", {{controller}}, :new
      {% elsif action == :edit %}
        get "{{path.id}}/:id/edit", {{controller}}, :edit
      {% elsif action == :create %}
        post "{{path.id}}", {{controller}}, :create
      {% elsif action == :update %}
        put "{{path.id}}/:id", {{controller}}, :update
        patch "{{path.id}}/:id", {{controller}}, :update
      {% elsif action == :destroy %}
        delete "{{path.id}}/:id", {{controller}}, :destroy
      {% else %}
        {% raise "Invalid route action '#{action}'" %}
      {% end %}
    end
  end
end
