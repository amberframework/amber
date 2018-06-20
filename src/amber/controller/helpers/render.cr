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
          %content = render_template("#{{{short_path.gsub(/\/[^\.\/]+\.ecr/, "")}}}/#{{{filename}}}", {{path}})
        {% else %}
          %content = render_template("#{{{short_path.gsub(/\_controller\.cr|\.cr/, "")}}}/#{{{filename}}}", {{path}})
        {% end %}
      {% end %}

      # Render Layout
      {% if layout && !partial %}
        content = %content
        render_template("layouts/#{{{layout.class_name == "StringLiteral" ? layout : LAYOUT}}}", {{path}})
      {% else %}
        %content
      {% end %}
    end

    private macro render_template(filename, path = "src/views")
      %full_filename = "#{{{path}}}/{{filename.id}}"
      __content_filename__ = %full_filename
      Kilt.render(%full_filename)
    end
  end
end
