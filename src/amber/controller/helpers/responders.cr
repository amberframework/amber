module Amber::Controller::Helpers
  module Responders
    TYPE_EXT_REGEX         = /\.(#{TYPE.keys.join("|")})$/
    ACCEPT_SEPARATOR_REGEX = /,|,\s/
    TYPE                   = {
      "html" => "text/html",
      "json" => "application/json",
      "txt" =>  "text/plain",
      "text" => "text/plain",
      "xml" =>  "application/xml",
    }

    alias ProcType = Proc(String) | Proc(Int32)

    class Content
      SUPPORTED_CONTENT_TYPES = %w[html json xml text]
      @content = {} of String => String? | Int32 | ProcType

      def initialize(@type : String)
      end

      {% for type in SUPPORTED_CONTENT_TYPES %}
        def {{type.id}}(content : Object)
          @content[{{type}}] ||= body(content) if @type == {{type}}
          self
        end
      {% end %}

      def json(**args : Object)
        @content["json"] ||= body(args.to_h)
        self
      end

      def response
        case content = @content[@type]
        when Proc then content.call
        else content
        end
      end

      private def body(content : String | ProcType)
        content
      end

      private def body(content : Hash(String | Symbol, String))
        content.to_json
      end
    end

    protected def respond_with(status_code = 200, &block)
      content = with Content.new(content_format) yield
      context.response.status_code = status_code
      context.response.content_type = TYPE[content_format]
      context.content = content.response.to_s
    end

    private def content_format
      format || "html"
    end
  end
end
