module Amber::Controller::Helpers
  module Responders
    Log = ::Log.for(self)

    alias ProcType = Proc(String) | Proc(Int32)

    class Content
      TYPE = {
        html: "text/html",
        json: "application/json",
        txt:  "text/plain",
        text: "text/plain",
        xml:  "application/xml",
        js:   "application/javascript",
      }

      TYPE_EXT_REGEX         = /\.(#{TYPE.keys.join("|")})$/
      ACCEPT_SEPARATOR_REGEX = /,|,\s/

      @requested_responses : Array(String)
      @available_responses = Hash(String, String | ProcType).new
      @type : String? = nil
      @body : String | Int32 | Nil = nil

      def initialize(@requested_responses)
      end

      {% for type in %w(html xml js json text) %}
        def {{type.id}}(value : String | ProcType)
          @available_responses[TYPE[:{{type.id}}]] = value
          self
        end

        def {{type.id}}(&block : -> _)
          {{type.id}}(block)
        end
      {% end %}

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
          case _body = @available_responses[type]?
          when Proc
            _body.call
          else
            _body
          end
        end
      end

      private def select_type
        raise "You must define at least one response_type." if @available_responses.empty?
        # NOTE: If only one response is requested or */* is present don't return anything else.
        if @requested_responses.size != 1 || @requested_responses.includes?("*/*")
          @requested_responses << @available_responses.keys.first
        end
        @requested_responses.find do |resp|
          @available_responses.keys.includes?(resp)
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
      path_ext = request.path.match(Content::TYPE_EXT_REGEX).try(&.[1])
      return [Content::TYPE[path_ext]] if path_ext
    end

    private def accepts_request_type
      accept = context.request.headers["Accept"]?
      if accept && !accept.empty?
        accepts = accept.split(";").first?.try(&.split(Content::ACCEPT_SEPARATOR_REGEX))
        return accepts if !accepts.nil? && accepts.any?
      end
    end

    private def requested_responses
      extension_request_type || accepts_request_type || [] of String
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
