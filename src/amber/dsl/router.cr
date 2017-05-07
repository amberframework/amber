module Amber::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Pipe::Router, valve : Symbol, scope : String do
    RESOURCES = [:get, :post, :put, :patch, :delete, :options, :head, :trace, :connect]

    macro route(verb, resource, controller, action)
      puts "{{verb.id}}  {{resource.id}}   {{controller.id}}   {{action.id}}"
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
      %route = Amber::Route.new(%verb, {{resource}}, %handler, {{action}}, valve, scope)

      router.add(%route)
    end

    {% for verb in RESOURCES %}
      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
      end

    {% end %}

    # TODO Clean this up
    macro resources(path, controller, actions = [:index, :edit, :new, :show, :create, :update, :delete])
      {% if actions.includes?(:index) %}
        get "{{path.id}}", {{controller}}, :index
      {% end %}
      {% if actions.includes?(:edit) %}
        get "{{path.id}}/:id/edit", {{controller}}, :edit
      {% end %}
      {% if actions.includes?(:new) %}
        get "{{path.id}}/new", {{controller}}, :new
      {% end %}
      {% if actions.includes?(:show) %}
        get "{{path.id}}/:id", {{controller}}, :show
      {% end %}
      {% if actions.includes?(:create) %}
        post "{{path.id}}", {{controller}}, :create
      {% end %}
      {% if actions.includes?(:update) %}
        patch "{{path.id}}/:id", {{controller}}, :update
        put "{{path.id}}/:id", {{controller}}, :update
      {% end %}
      {% if actions.includes?(:delete) %}
        delete "{{path.id}}/:id", {{controller}}, :delete
      {% end %}
    end
  end
end
