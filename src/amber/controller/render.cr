module Amber::Controller
  module Render
    LAYOUT = "application.slang"

    private macro render_template(filename, path = "src/views")
      {% if filename.id.split("/").size > 2 %}
        Kilt.render("{{filename.id}}")
      {% else %}
        Kilt.render("#{{{path}}}/{{filename.id}}")
      {% end %}
    end

    macro render(template = nil, partial = nil, layout = true, path = "src/views", folder = __FILE__)
      {% if template || partial %}
        {{filename = template || partial}}

        {% if filename.id.split("/").size > 1 %}
          %content = render_template("#{{{filename}}}", {{path}})
        {% else %}
          {% if folder.id.ends_with?(".ecr") %}
            %content = render_template("#{{{folder.split("/")[-2]}}}/#{{{filename}}}", {{path}})
          {% else %}
            %content = render_template("#{{{folder.split("/").last.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}", {{path}})
          {% end %}
        {% end %}

        {% if layout && !partial %}
          content = %content
          %content = render_template("layouts/#{{{layout.class_name == "StringLiteral" ? layout : LAYOUT}}}", {{path}})
        {% else %}
          %content
        {% end %}
      {% else %}
        raise "Template or partial required!"
      {% end %}
    end
  end
end
