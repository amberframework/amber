require "../../spec_helper"

module Amber
  module Pipe
    describe Params do
      it "parses query params" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["test"].should eq "test"
      end

      it "parses multiple query params" do
        request = HTTP::Request.new("GET", "/?test=test&test2=test2")
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["test2"].should eq "test2"
      end

      it "parses body params" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        body = "test=test"
        request = HTTP::Request.new("POST", "/", headers, body)
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["test"].should eq "test"
      end

      it "parses body params with charset" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        body = "\x68\x65\x6C\x6C\x6F\x3D\x77\x6F\x72\x6C\x64"
        request = HTTP::Request.new("POST", "/", headers, body)
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["hello"]?.should eq "world"
      end

      it "parses multiple body params" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        body = "test=test&test2=test2"
        request = HTTP::Request.new("POST", "/", headers, body)
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["test2"].should eq "test2"
      end

      it "parses json hash" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/json"
        body = "{\"test\":\"test\"}"
        request = HTTP::Request.new("POST", "/", headers, body)
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["test"].should eq "test"
      end

      it "parses json array" do
        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/json"
        body = "[\"test\",\"test2\"]"
        request = HTTP::Request.new("POST", "/", headers, body)
        context = create_context(request)
        params = Params.instance

        params.call(context)

        context.params["_json"].should eq "[\"test\", \"test2\"]"
      end
    end
  end
end
