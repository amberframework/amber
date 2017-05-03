module Amber::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Pipe::Router do
    macro route(verb, resource, controller, action, pipeline)
      %controller = {{controller.id}}.new
      %handler = ->%controller.{{action.id}}
      %verb = {{verb.upcase.id.stringify}}
      %route = Amber::Route.new(%verb, {{resource}}, %controller, %handler, {{action}}, {{pipeline}})

      router.add(%route)
    end

    {% for verb in {:get, :post, :put, :delete, :options, :head, :trace, :connect} %}

      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
      end

    {% end %}
  end
end
