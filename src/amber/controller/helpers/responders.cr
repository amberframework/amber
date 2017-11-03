module Amber::Controller::Helpers
  module Responders
    class Content
      TYPE = {html: "text/html", json: "application/json", text: "text/plain", xml: "application/xml"}
      @accepts : String
      @available_responses = Hash(String, String).new
      @type : String? = nil 
      @body : String? = nil

      def initialize(@accepts)
      end

      # TODO: add JS type simlar to rails.
      def html(html : String)
        @available_responses[TYPE[:html]] = html; self
      end

      def xml(xml : String)
        @available_responses[TYPE[:xml]] = xml; self
      end

      def json(json : String | Hash(String | String))
        @available_responses[TYPE[:json]] = json.is_a?(String) ? json : json.to_json; self
      end

      def text(text : String)
        @available_responses[TYPE[:text]] = text; self
      end

      def type
        unless @type && @body
          parse_accepts if @accepts.size > 3
          choose_type_and_body
        end
        @type.to_s
      end

      def body
        (type && @body).to_s
      end

      private def parse_accepts
        requested_resp = @accepts.split(";").first?.try(&.split(/,|,\s/))
        if requested_resp 
          @type = requested_resp.find do |resp| 
            @available_responses.keys.includes?(resp)
          end
        end
      end

      private def choose_type_and_body
        if @type
          @body = @available_responses[@type]
        else 
          @type, @body = @available_responses.first
        end
      end
    end

    protected def respond_with(&block)
      content = with Content.new(context.request.headers["Accept"]) yield
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
