module Amber::Controller
  module Render
    LAYOUT = "application.slang"

    macro set_layout(filename)
      LAYOUT = {{filename}}
    end

    macro render_template(filename, path = "src/views")
      {% if filename.id.split("/").size > 2 %}
        Kilt.render("{{filename.id}}")
      {% else %}
        Kilt.render("#{{{path}}}/{{filename.id}}")
      {% end %}
    end

    macro render(filename, layout = true, path = "src/views", folder = __FILE__)
      {% if filename.id.split("/").size > 1 %}
        content = render_template("#{{{filename}}}", {{path}})
      {% else %}
        content = render_template("#{{{folder.split("/").last.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}", {{path}})
      {% end %}

      {% if layout && !filename.id.split("/").last.starts_with?("_") %}
        content = render_template("layouts/#{{{layout.class_name == "StringLiteral" ? layout : LAYOUT}}}", {{path}})
      {% end %}
      content
    end
  end
end

