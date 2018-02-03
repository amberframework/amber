require "../../../spec_helper"

module Amber::Router
  describe Parse do
    context "when parsing query string" do
      it "returns query params" do
        request = HTTP::Request.new("GET", "/?test=test")
        params = Parse.new(request).parse
        params["test"].should eq "test"
      end

      it "returns array of values for same param key" do
        request = HTTP::Request.new("GET", "/?test=test&test=test2")
        params = Parse.new(request).parse
        params.fetch_all("test").size.should eq 2
        params.fetch_all("test").should eq %w(test test2)
      end
    end

    context "when parsing body params" do
      context "when content-type is form url urlencoded" do
        it "returns params" do
          headers = HTTP::Headers.new
          headers["Content-Type"] = "application/x-www-form-urlencoded"
          body = "name=John Doe"
          request = HTTP::Request.new("POST", "/", headers, body)
          params = Parse.new(request).parse

          params["name"].should eq "John Doe"
        end

        it "parses body params with charset" do
          headers = HTTP::Headers.new
          headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
          body = "\x68\x65\x6C\x6C\x6F\x3D\x77\x6F\x72\x6C\x64"
          request = HTTP::Request.new("POST", "/", headers, body)
          params = Parse.new(request).parse
          params["hello"].should eq "world"
        end


      end
    end
  end
end