module Amber::Controller::Helpers
  module Render
    LAYOUT = "application.slang"
    CONTENT_FOR_BLOCKS = Hash(String, Tuple(String, Proc(String))).new

    macro content_for(key, file = __FILE__)
      %proc = ->() {
        __kilt_io__ = IO::Memory.new
        {{ yield }}
        __kilt_io__.to_s
      }

      CONTENT_FOR_BLOCKS[{{key}}] = Tuple.new {{file}}, %proc
      nil
    end
    
    macro yield_content(key)
      if CONTENT_FOR_BLOCKS.has_key?({{key}})
        __caller_filename__ = CONTENT_FOR_BLOCKS[{{key}}][0]
        %proc = CONTENT_FOR_BLOCKS[{{key}}][1]
        %proc.call if __content_filename__ == __caller_filename__
      end
    end

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
          __content_filename__ = "#{{{path}}}/#{{{short_path.gsub(/\/[^\.\/]+\.ecr/, "")}}}/#{{{filename}}}" # -- 
          %content = render_template("#{{{path}}}/#{{{short_path.gsub(/\/[^\.\/]+\.ecr/, "")}}}/#{{{filename}}}")
        {% else %}
          __content_filename__ = "#{{{path}}}/#{{{short_path.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}" # -- 
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
  end
end
