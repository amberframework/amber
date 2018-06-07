module Amber::DSL
  RESOURCEFUL_VERBS = [:get, :post, :put, :patch, :delete, :options, :head, :trace, :connect]
  RESOURCEFUL_ACTIONS = [:index, :new, :create, :show, :edit, :update, :destroy]

  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Amber::Router::Router, valve : Symbol, scope : String do
    macro route(verb, resource, controller, action)
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
        %verb, {{resource}}, %handler, {{action}}, valve, scope, "{{controller.id}}"
      )

      router.add(%route)
    end

    {% for verb in RESOURCEFUL_VERBS %}
      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
        {% if verb == :get %}
          route :head, \{{*args}}
        {% end %}
        route {{verb}}, \{{*args}}
        {% if ![:trace, :connect, :options, :head].includes? verb %}
          route :options, \{{*args}}
        {% end %}
      end
    {% end %}

    macro resources(resource, controller, only = nil, except = nil)
      base_resources(resources, controller, only, except, Amber::DSL::RESOURCEFUL_ACTIONS)
    end

    macro api_resources(resource, controller, only = nil, except = nil)
      base_resources(resources, controller, only, except, Amber::DSL::RESOURCEFUL_ACTIONS.reject{|a| [:new, :edit].includes?(a)})
    end

    private macro base_resources(resource, controller, only = nil, except = nil, actions = Amber::DSL::RESOURCEFUL_ACTIONS)
      {% if only %}
        {% actions = only %}
      {% elsif except %}
        {% actions = actions.reject { |a| except.includes?(a)} %}
      {% end %}

      {% for action in actions %}
        define_action({{resource}}, {{controller}}, {{action}})
      {% end %}
    end

    private macro define_action(path, controller, action)
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

  def websocket(path, app_socket)
    Amber::WebSockets::Server.create_endpoint(path, app_socket)
  end
end
end
