module Amber::Controller::Helpers
  module Responders
    Log = ::Log.for(self)

    alias ProcType = Proc(String) | Proc(Int32)

    struct Content
      TYPE = {
        html:     "text/html",
        json:     "application/json; charset=utf-8",
        txt:      "text/plain",
        text:     "text/plain",
        xml:      "application/xml",
        js:       "text/javascript",
        md:       "text/markdown; charset=utf-8",
        markdown: "text/markdown; charset=utf-8",
      }

      TYPE_EXT_REGEX         = /\.(#{TYPE.keys.join("|")})$/
      ACCEPT_SEPARATOR_REGEX = /,|,\s/

      @requested_responses : String | Array(String) | Nil
      @html_response : String | ProcType | Nil
      @xml_response : String | ProcType | Nil
      @js_response : String | ProcType | Nil
      @json_response : String | ProcType | Nil
      @text_response : String | ProcType | Nil
      @markdown_response : String | ProcType | Nil
      @response_order : UInt16
      @response_mask : UInt8
      @response_count : UInt8
      @type : String? = nil
      @body : String | Int32 | Nil = nil

      def initialize(@requested_responses)
        @response_order = 0_u16
        @response_mask = 0_u8
        @response_count = 0_u8
      end

      {% for type, index in %w(html xml js json text markdown) %}
        def {{type.id}}(value : String | ProcType)
          register_response({{index}}_u8)
          @{{type.id}}_response = value
          self
        end

        def {{type.id}}(&block : -> _)
          {{type.id}}(block)
        end
      {% end %}

      # Short alias for Markdown response blocks.
      def md(value : String | ProcType)
        markdown(value)
      end

      def md(&block : -> _)
        markdown(block)
      end

      def json(value : Hash(Symbol | String, String))
        json(value.to_json)
      end

      def json(**args : Object)
        json(args.to_h)
      end

      def type
        (@type ||= select_type).to_s
      end

      def body
        @body ||= begin
          case _body = response_for(type)
          when Proc
            _body.call
          else
            _body
          end
        end
      end

      private def select_type
        raise "You must define at least one response_type." if @response_count == 0
        case requested = @requested_responses
        when String
          if requested == "*/*"
            first_available_type
          else
            available_type_for(requested)
          end
        when Array
          requested.each do |response|
            if available_type = available_type_for(response)
              return available_type
            end
          end
          if requested.size != 1 || requested.includes?("*/*")
            first_available_type
          end
        else
          first_available_type
        end
      end

      private def first_available_type : String
        type_for(response_id_at(0_u8))
      end

      private def available_type_for(requested : String) : String?
        index = 0_u8
        while index < @response_count
          available = type_for(response_id_at(index))
          return available if available.includes?(requested)
          index &+= 1
        end
        nil
      end

      private def register_response(id : UInt8) : Nil
        bit = 1_u8 << id
        return unless @response_mask & bit == 0

        @response_order |= id.to_u16 << (@response_count * 3)
        @response_mask |= bit
        @response_count &+= 1
      end

      private def response_for(type : String) : String | ProcType | Nil
        case type
        when TYPE[:html]     then @html_response
        when TYPE[:xml]      then @xml_response
        when TYPE[:js]       then @js_response
        when TYPE[:json]     then @json_response
        when TYPE[:text]     then @text_response
        when TYPE[:markdown] then @markdown_response
        end
      end

      private def response_id_at(index : UInt8) : UInt8
        ((@response_order >> (index * 3)) & 0b111).to_u8
      end

      private def type_for(id : UInt8) : String
        case id
        when 0 then TYPE[:html]
        when 1 then TYPE[:xml]
        when 2 then TYPE[:js]
        when 3 then TYPE[:json]
        when 4 then TYPE[:text]
        when 5 then TYPE[:markdown]
        else        raise "Unknown response type"
        end
      end
    end

    def set_response(body, status_code = 200, content_type = Content::TYPE[:html])
      if context.response.status_code == 200
        context.response.status_code = status_code
      else
        Log.error { "Setting response status_code would overwrite previous value" }
      end
      context.response.content_type = content_type
      context.content = body
    end

    private def extension_request_type
      path = request.path
      return unless path.includes?('.')

      path_ext = path.match(Content::TYPE_EXT_REGEX).try(&.[1])
      return Content::TYPE[path_ext] if path_ext
    end

    private def accepts_request_type
      accept = context.request.headers["Accept"]?
      if accept && !accept.empty?
        if accept.in?("*/*", "text/html", "application/json", "application/xml", "text/javascript", "text/plain")
          return accept
        end

        # RFC 7231: split on "," first into media-range segments,
        # then strip quality/extension params (";<params>") from each segment.
        accepts = accept.split(Content::ACCEPT_SEPARATOR_REGEX).map do |part|
          part.split(";").first.strip
        end.reject(&.empty?)
        return accepts unless accepts.empty?
      end
    end

    private def requested_responses
      extension_request_type || accepts_request_type
    end

    protected def respond_with(status_code = 200, &block)
      content = with Content.new(requested_responses) yield
      if content.body
        set_response(body: content.body.to_s, status_code: status_code, content_type: content.type)
      else
        set_response(body: "Response Not Acceptable.", status_code: 406, content_type: Content::TYPE[:text])
      end
    end
  end
end
