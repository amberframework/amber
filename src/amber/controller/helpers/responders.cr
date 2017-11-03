module Amber::Controller::Helpers
  module Responders
    class Content
      TYPE = {html: "text/html", json: "application/json", text: "text/plain", xml: "application/xml"}
      @requested_responses : Array(String)
      @available_responses = Hash(String, String).new
      @type : String? = nil

      def initialize(@requested_responses)
      end

      # TODO: add JS type simlar to rails.
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
        select_type.to_s
      end

      def body
        @available_responses[type]
      end

      private def select_type
        @type ||= begin
          raise "You must define at least one response_type." if @available_responses.empty?
          @requested_responses << @available_responses.keys.first
          @requested_responses.find do |resp|
            @available_responses.keys.includes?(resp)
          end
        end
      end
    end

    private def requested_responses
      req_responses = Array(String).new

      if (accept = context.request.headers["Accept"]?) && !accept.empty?
        accepts = accept.split(";").first?.try(&.split(/,|,\s/))
        req_responses.concat(accepts) if accepts.is_a?(Array) && accepts.any?
      end
      req_responses
    end

    protected def respond_with(&block)
      content = with Content.new(requested_responses) yield
      if content.body
        set_response(body: content.body, status_code: 200, content_type: content.type)
      else
        set_response(body: "Response unexceptable.", status_code: 406, content_type: Content::TYPE[:text])
      end
    end

    private def set_response(body, status_code = 200, content_type = Content::TYPE[:html])
      context.response.status_code = status_code
      context.response.content_type = content_type
      context.content = body
    end
  end
end
