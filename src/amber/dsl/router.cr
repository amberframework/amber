module Amber::DSL
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

  module ControllerActions
    macro render_both(filename, layout)
      content = render_template("{{filename.id}}")
      render_template("{{layout.id}}")
    end

    # helper to render a template.  The view name is relative to `src/views` directory.
    macro render_template(filename, *args)
      {% if filename.id.split("/").size > 2 %}
        Kilt.render("{{filename.id}}", {{*args}})
      {% else %}
        Kilt.render("src/views/{{filename.id}}", {{*args}})
      {% end %}
    end

    macro render(filename, layout = "layouts/application.slang", path = "src/views", folder = __FILE__)
      render_both "#{{{path}}}/#{{{folder.split("/").last.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}", "#{{{path}}}/#{{{layout}}}"
    end
  end
end
