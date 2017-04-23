module Amber::Support::DSL
  record Pipeline, pipeline : Pipe::Pipeline do
    def plug(pipe)
      pipeline.plug pipe
    end
  end

  record Router, router : Pipe::Router do
    macro route(verb, resource, controller, handler, pipeline)
      %ctrl = {{controller.id}}.new
      %action = ->%ctrl.{{handler.id}}
      %verb = {{verb.upcase.id.stringify}}
      %route = Amber::Route.new(%verb, {{resource}}, %ctrl, %action, {{pipeline}})

      router.add(%route)
    end

    {% for verb in {:get, :post, :put, :delete, :options, :head, :trace, :connect} %}

      macro {{verb.id}}(*args)
        route {{verb}}, \{{*args}}
      end

    {% end %}
  end
end
