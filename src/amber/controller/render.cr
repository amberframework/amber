module Amber::Controller
  module Render
    LAYOUT = "application.slang"

    macro render(template = nil, layout = true, partial = nil, path = "src/views", folder = __FILE__)
      {% if !(template || partial) %}
        raise "Template or partial required!"
      {% end %}

      {{ filename = template || partial }}
       
      # Render Template and return content
      {% if filename.id.split("/").size > 1 %}
        %content = render_template("#{{{filename}}}", {{path}})
      {% else %}
        {{ short_path = folder.gsub(/^.+?(?:controllers|views)\//, "") }}
        {% if folder.id.ends_with?(".ecr") %}
          %content = render_template("#{{{path}}}/#{{{short_path.gsub(/\/[^\.\/]+\.ecr/, "")}}}/#{{{filename}}}")
        {% else %}
          %content = render_template("#{{{path}}}/#{{{short_path.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}")
        {% end %}
      {% end %}
      
      # Render Layout
      {% if layout && !partial %}
        content = %content
        render_template("#{{{path}}}/layouts/#{{{layout.class_name == "StringLiteral" ? layout : LAYOUT}}}")
      {% else %}
        %content
      {% end %}
    end

    private macro render_template(filename, path = "src/views")
      {% if filename.id.split("/").size > 2 %}
        Kilt.render("{{filename.id}}")
      {% else %}
        Kilt.render("#{{{path}}}/{{filename.id}}")
      {% end %}
    end

    def respond_with(html : String? = nil, json : Hash | String? = nil, xml : String? = nil, text : String? = nil)
      accepts = context.request.headers["Accept"].split(";").try(&.split(","))

      if accepts.includes?("text/plain") && text
        render_text(text)
      elsif accepts.includes?("text/json") && json
        render_json(json)
      elsif accepts.includes?("text/xml") && xml
        render_xml(xml)
      elsif accepts.includes?("text/html") && html
        render_html(html)
      else
        render_text("Response not acceptable", 406)
      end
    end

    private def render_text(body, status_code = 200)
      context.response.status_code = status_code
      context.response.content_type = "text/plain"
      context.content = body
    end

    private def render_json(body, status_code = 200)
      context.response.status_code = status_code
      context.response.content_type = "text/json"
      context.content = body
    end

    private def render_html(body, status_code = 200)
      context.response.status_code = status_code
      context.response.content_type = "text/html"
      context.content = body
    end

    private def render_xml(body, status_code = 200)
      context.response.status_code = status_code
      context.response.content_type = "text/xml"
      context.content = body
    end

  end
end
