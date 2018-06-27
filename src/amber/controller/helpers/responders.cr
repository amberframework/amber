module Amber::Controller::Helpers
  module Responders
    alias ProcType = Proc(String) | Proc(Int32)

    class Content
      UNACCEPTABLE = "Response Not Acceptable."
      SUPPORTED_CONTENT_TYPES = %w[html json xml text]
      @content = {} of String => String? | Int32 | ProcType

      def initialize(@request_type : String)
      end

      {% for type in SUPPORTED_CONTENT_TYPES %}
        def {{type.id}}(content)
          mime_type = mime({{type}})
          @content[mime_type] ||= body(content) if @request_type == mime_type
          self
        end
      {% end %}

      def json(**args : Object)
        @content["application/json"] ||= body(args.to_h)
        self
      end

      def response
        case content = @content[@request_type]?
        when Proc then content.call
        when Nil then UNACCEPTABLE
        else content
        end
      end

      def unacceptable?
        response == UNACCEPTABLE
      end


      private def body(content : String | ProcType)
        content
      end

      private def body(content : Hash(String | Symbol, String))
        content.to_json
      end

      private def mime(type)
        Amber::Support::MimeTypes.mime_type(type)
      end
    end

    protected def respond_with(status_code = 200, &block)
      content = with Content.new(mime_type) yield
      status_code = content.unacceptable? ? 406 : status_code
      response.status_code = status_code
      response.content_type = mime_type
      context.content = content.response.to_s
    end

    private def content_format
      format || "html"
    end

    private def mime_type
      Amber::Support::MimeTypes.mime_type(content_format)
    end
  end
end
