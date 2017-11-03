module Amber::Controller
  module Render
    class Content
      TYPE = { html: "text/html", json: "application/json", text: "text/plain", xml: "application/xml" }
      getter html : String? = nil
      getter xml : String? = nil
      getter json : Hash(String, String) | String? = nil
      getter text : String? = nil
     
      def html(html : String)
        @html = html; self
      end

      def xml(xml : String)
        @xml = xml; self
      end

      def json(json : String | Hash(String | String))
        @json = json; self
      end

      def text(text : String)
        @text = text; self
      end
    end

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

    protected def respond_with(html : String? = nil, json : Hash | String? = nil, xml : String? = nil, text : String? = nil)
      puts context.request.headers["Accept"]
      accepts = context.request.headers["Accept"].split(";").first.try(&.split(/,|,\s/))
      # TODO: add JS type simlar to rails.
      if accepts.includes?(Content::TYPE[:html]) && html
        respond_with_html(html)
      elsif accepts.includes?(Content::TYPE[:json]) && json
        respond_with_json(json.is_a?(Hash) ? json.to_json : json)
      elsif accepts.includes?(Content::TYPE[:xml]) && xml
        respond_with_xml(xml)
      elsif accepts.includes?(Content::TYPE[:text]) && text
        respond_with_text(text)
      elsif html
        respond_with_html(html)
      elsif text
        respond_with_text(text)
      elsif json
        respond_with_json(json.is_a?(Hash) ? json.to_json : json)
      elsif xml
        respond_with_xml(xml)
      else
        respond_with_text("Response not acceptable", 406)
      end
    end

    protected def respond_with(&block)
      response = yield(Content.new)
      pp response
      respond_with(response.html, response.json, response.xml, response.text)
    end

    protected def respond_with_html(body, status_code = 200)
      set_response(body, status_code, Content::TYPE[:html])
    end

    protected def respond_with_text(body, status_code = 200)
      set_response(body, status_code, Content::TYPE[:text])
    end

    protected def respond_with_json(body, status_code = 200)
      set_response(body, status_code, Content::TYPE[:json])
    end

    protected def respond_with_xml(body, status_code = 200)
      set_response(body, status_code, Content::TYPE[:xml])
    end

    private def set_response(body, status_code = 200, content_type = Content::TYPE[:html])
      context.response.status_code = status_code
      context.response.content_type = content_type 
      context.content = body
    end
  end
end
