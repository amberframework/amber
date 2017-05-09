module Amber::Controller
  module Render
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
