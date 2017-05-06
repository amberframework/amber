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
      %controller = {{controller.id}}.new
      %handler = ->%controller.{{action.id}}
      %verb = {{verb.upcase.id.stringify}}
      %route = Amber::Route.new(%verb, {{resource}}, %controller, %handler, {{action}}, valve, scope)

      router.add(%route)
    end

    {% for verb in RESOURCES %}

      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
      end

    {% end %}

    # TODO Clean this up
    macro resources(path, controller, actions = [:index, :edit, :new, :show, :create, :update, :put, :delete])
      get "{{path.id}}", {{controller}}, :index if {{actions}}.includes?(:index)
      get "{{path.id}}/:id/edit", {{controller}}, :edit  if {{actions}}.includes?(:edit)
      get "{{path.id}}/new", {{controller}}, :new if {{actions}}.includes?(:new)
      get "{{path.id}}/:id", {{controller}}, :show if {{actions}}.includes?(:show)
      post "{{path.id}}", {{controller}}, :create if {{actions}}.includes?(:create)
      patch "{{path.id}}/:id", {{controller}}, :update if {{actions}}.includes?(:update)
      put "{{path.id}}/:id", {{controller}}, :update if {{actions}}.includes?(:update)
      delete "{{path.id}}/:id", {{controller}}, :delete if {{actions}}.includes?(:delete)
    end
  end
end
