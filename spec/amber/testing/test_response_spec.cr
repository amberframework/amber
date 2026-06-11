require "../../spec_helper"
require "../../../src/amber/testing"

describe Amber::Testing::TestResponse do
  describe "#successful?" do
    it "returns true for 200" do
      response = Amber::Testing::TestResponse.new(200, "OK", HTTP::Headers.new)
      response.successful?.should be_true
    end

    it "returns true for 201" do
      response = Amber::Testing::TestResponse.new(201, "Created", HTTP::Headers.new)
      response.successful?.should be_true
    end

    it "returns true for 204" do
      response = Amber::Testing::TestResponse.new(204, "", HTTP::Headers.new)
      response.successful?.should be_true
    end

    it "returns false for 301" do
      response = Amber::Testing::TestResponse.new(301, "", HTTP::Headers.new)
      response.successful?.should be_false
    end

    it "returns false for 404" do
      response = Amber::Testing::TestResponse.new(404, "", HTTP::Headers.new)
      response.successful?.should be_false
    end

    it "returns false for 500" do
      response = Amber::Testing::TestResponse.new(500, "", HTTP::Headers.new)
      response.successful?.should be_false
    end
  end

  describe "#redirect?" do
    it "returns true for 301" do
      response = Amber::Testing::TestResponse.new(301, "", HTTP::Headers.new)
      response.redirect?.should be_true
    end

    it "returns true for 302" do
      response = Amber::Testing::TestResponse.new(302, "", HTTP::Headers.new)
      response.redirect?.should be_true
    end

    it "returns true for 303" do
      response = Amber::Testing::TestResponse.new(303, "", HTTP::Headers.new)
      response.redirect?.should be_true
    end

    it "returns false for 200" do
      response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
      response.redirect?.should be_false
    end
  end

  describe "#client_error?" do
    it "returns true for 400" do
      response = Amber::Testing::TestResponse.new(400, "", HTTP::Headers.new)
      response.client_error?.should be_true
    end

    it "returns true for 404" do
      response = Amber::Testing::TestResponse.new(404, "", HTTP::Headers.new)
      response.client_error?.should be_true
    end

    it "returns true for 422" do
      response = Amber::Testing::TestResponse.new(422, "", HTTP::Headers.new)
      response.client_error?.should be_true
    end

    it "returns false for 200" do
      response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
      response.client_error?.should be_false
    end

    it "returns false for 500" do
      response = Amber::Testing::TestResponse.new(500, "", HTTP::Headers.new)
      response.client_error?.should be_false
    end
  end

  describe "#server_error?" do
    it "returns true for 500" do
      response = Amber::Testing::TestResponse.new(500, "", HTTP::Headers.new)
      response.server_error?.should be_true
    end

    it "returns true for 503" do
      response = Amber::Testing::TestResponse.new(503, "", HTTP::Headers.new)
      response.server_error?.should be_true
    end

    it "returns false for 200" do
      response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
      response.server_error?.should be_false
    end

    it "returns false for 404" do
      response = Amber::Testing::TestResponse.new(404, "", HTTP::Headers.new)
      response.server_error?.should be_false
    end
  end

  describe "#json" do
    it "parses a valid JSON body" do
      body = %({"name": "Alice", "age": 30})
      response = Amber::Testing::TestResponse.new(200, body, HTTP::Headers.new)
      json = response.json
      json["name"].as_s.should eq("Alice")
      json["age"].as_i.should eq(30)
    end

    it "raises on invalid JSON body" do
      response = Amber::Testing::TestResponse.new(200, "not json", HTTP::Headers.new)
      expect_raises(JSON::ParseException) do
        response.json
      end
    end

    it "parses a JSON array body" do
      body = %([1, 2, 3])
      response = Amber::Testing::TestResponse.new(200, body, HTTP::Headers.new)
      json = response.json
      json.as_a.size.should eq(3)
    end
  end

  describe "#redirect_url" do
    it "returns the Location header value" do
      headers = HTTP::Headers{"Location" => "/dashboard"}
      response = Amber::Testing::TestResponse.new(302, "", headers)
      response.redirect_url.should eq("/dashboard")
    end

    it "returns nil when no Location header" do
      response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
      response.redirect_url.should be_nil
    end
  end

  describe "#content_type" do
    it "returns the Content-Type header value" do
      headers = HTTP::Headers{"Content-Type" => "application/json"}
      response = Amber::Testing::TestResponse.new(200, "", headers)
      response.content_type.should eq("application/json")
    end

    it "returns nil when no Content-Type header" do
      response = Amber::Testing::TestResponse.new(200, "", HTTP::Headers.new)
      response.content_type.should be_nil
    end
  end

  describe ".from_client_response" do
    it "builds from an HTTP::Client::Response" do
      io = IO::Memory.new
      server_response = HTTP::Server::Response.new(io)
      server_response.status_code = 201
      server_response.headers["X-Custom"] = "test-value"
      server_response.print("response body")
      server_response.close

      io.rewind
      client_response = HTTP::Client::Response.from_io(io, decompress: false)
      test_response = Amber::Testing::TestResponse.from_client_response(client_response)

      test_response.status_code.should eq(201)
      test_response.body.should eq("response body")
      test_response.headers["X-Custom"].should eq("test-value")
    end
  end
end
