require "../../../spec_helper"

module Amber::Router::Parsers
  describe FormData do
    describe ".parse" do
      it "leaves the request body readable after parsing the form" do
        form_body = "title=Hello&_csrf=token-value"
        headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
        request = HTTP::Request.new("POST", "/", headers, form_body)

        form = FormData.parse(request)

        form["title"].should eq "Hello"
        body_after_parse = request.body
        body_after_parse.should_not be_nil
        body_after_parse.as(IO).gets_to_end.should eq form_body
      end

      it "returns empty params for a request without a body" do
        request = HTTP::Request.new("POST", "/")

        FormData.parse(request).size.should eq 0
      end
    end
  end

  describe "a :web form POST that the CSRF pipe already parsed" do
    it "still hands the controller the full request body" do
      form_body = "_csrf=token-value&message=Hello+there"
      headers = HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}
      request = HTTP::Request.new("POST", "/", headers, form_body)

      request.params["_csrf"].should eq "token-value"
      body_after_parse = request.body
      body_after_parse.should_not be_nil
      body_after_parse.as(IO).gets_to_end.should eq form_body
      request.params["message"].should eq "Hello there"
    end
  end
end
