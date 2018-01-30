module Amber::Controller::Helpers
  module Responders
    class Content
      TYPE = {
        html: "text/html",
        json: "application/json",
        txt:  "text/plain",
        text: "text/plain",
        xml:  "application/xml",
      }

      TYPE_EXT_REGEX         = /\.(#{TYPE.keys.join("|")})$/
      ACCEPT_SEPARATOR_REGEX = /,|,\s/

      @requested_responses : Array(String)
      @available_responses = Hash(String, String).new
      @type : String? = nil

      def initialize(@requested_responses)
      end

      # TODO: add JS type similar to rails.
      def html(html : String)
        @available_responses[TYPE[:html]] = html; self
      end

      def xml(xml : String)
        @available_responses[TYPE[:xml]] = xml; self
      end

      def json(json : String | Hash(Symbol | String, String))
        @available_responses[TYPE[:json]] = json.is_a?(String) ? json : json.to_json; self
      end

      def json(**args : Object)
        json(args.to_h)
      end

      def text(text : String)
        @available_responses[TYPE[:text]] = text; self
      end

      def type
        (@type ||= select_type).to_s
      end

      def body
        @available_responses[type]?
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

    protected def respond_with(&block)
      content = with Content.new(requested_responses) yield
      if content.body
        set_response(body: content.body, status_code: 200, content_type: content.type)
      else
        set_response(body: "Response Not Acceptable.", status_code: 406, content_type: Content::TYPE[:text])
      end
    end

    private def set_response(body, status_code = 200, content_type = Content::TYPE[:html])
      context.response.status_code = status_code
      context.response.content_type = content_type
      context.content = body
    end
  end
end
