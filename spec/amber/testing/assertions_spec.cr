require "../../spec_helper"
require "../../../src/amber/testing"

module AssertionsSpec
  extend Amber::Testing::Assertions

  describe Amber::Testing::Assertions do
    describe "#assert_response_status" do
      it "passes when the status matches" do
        response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_status(response, 200)
      end
    end

    describe "#assert_response_success" do
      it "passes for a 200 response" do
        response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_success(response)
      end

      it "passes for a 201 response" do
        response = Amber::Testing::TestResponse.new(201, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_success(response)
      end
    end

    describe "#assert_response_redirect" do
      it "passes for a 302 response" do
        response = Amber::Testing::TestResponse.new(302, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_redirect(response)
      end

      it "passes for a 301 response" do
        response = Amber::Testing::TestResponse.new(301, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_redirect(response)
      end
    end

    describe "#assert_redirect_to" do
      it "passes when redirect URL matches" do
        headers = HTTP::Headers{"Location" => "/dashboard"}
        response = Amber::Testing::TestResponse.new(302, "", headers)
        AssertionsSpec.assert_redirect_to(response, "/dashboard")
      end
    end

    describe "#assert_response_client_error" do
      it "passes for a 404 response" do
        response = Amber::Testing::TestResponse.new(404, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_client_error(response)
      end

      it "passes for a 422 response" do
        response = Amber::Testing::TestResponse.new(422, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_client_error(response)
      end
    end

    describe "#assert_response_not_found" do
      it "passes for a 404 response" do
        response = Amber::Testing::TestResponse.new(404, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_not_found(response)
      end
    end

    describe "#assert_response_server_error" do
      it "passes for a 500 response" do
        response = Amber::Testing::TestResponse.new(500, "", HTTP::Headers.new)
        AssertionsSpec.assert_response_server_error(response)
      end
    end

    describe "#assert_content_type" do
      it "passes when content type contains the expected string" do
        headers = HTTP::Headers{"Content-Type" => "application/json; charset=utf-8"}
        response = Amber::Testing::TestResponse.new(200, "", headers)
        AssertionsSpec.assert_content_type(response, "application/json")
      end
    end

    describe "#assert_json_content_type" do
      it "passes when content type is JSON" do
        headers = HTTP::Headers{"Content-Type" => "application/json"}
        response = Amber::Testing::TestResponse.new(200, "", headers)
        AssertionsSpec.assert_json_content_type(response)
      end
    end

    describe "#assert_html_content_type" do
      it "passes when content type is HTML" do
        headers = HTTP::Headers{"Content-Type" => "text/html"}
        response = Amber::Testing::TestResponse.new(200, "", headers)
        AssertionsSpec.assert_html_content_type(response)
      end
    end

    describe "#assert_body_contains" do
      it "passes when body contains the expected text" do
        response = Amber::Testing::TestResponse.new(200, "Hello, World!", HTTP::Headers.new)
        AssertionsSpec.assert_body_contains(response, "World")
      end
    end

    describe "#assert_json_body" do
      it "returns parsed JSON from the body" do
        body = %({"status": "ok"})
        response = Amber::Testing::TestResponse.new(200, body, HTTP::Headers.new)
        json = AssertionsSpec.assert_json_body(response)
        json["status"].as_s.should eq("ok")
      end
    end

    describe "#assert_header" do
      it "passes when the header matches" do
        headers = HTTP::Headers{"X-Custom" => "value123"}
        response = Amber::Testing::TestResponse.new(200, "", headers)
        AssertionsSpec.assert_header(response, "X-Custom", "value123")
      end
    end
  end
end
