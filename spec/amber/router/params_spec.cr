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

      context "when parsing multipart" do
        it "parses files from multipart forms" do
          headers = HTTP::Headers.new
          headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX"
          body = "--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\nPcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\ntitle field\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"picture\"; filename=\"index.html\"\r\nContent-Type: text/html\r\n\r\n<head></head><body>Hello World!</body>\r\n\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nseriously\r\n--fhhRFLCazlkA0dX--"
          request = HTTP::Request.new("POST", "/", headers, body)

          params = Parse.new(request).parse

          params.files["picture"].filename.should eq "index.html"
          params["title"].should eq "title field"
          params["_csrf"].should eq "PcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI"
        end
      end

      context "when parsing JSON body" do
        it "parses json hash" do
          headers = HTTP::Headers.new
          headers["Content-Type"] = "application/json"
          body = %({ "test": "test", "address": { "city": "New York" }})
          request = HTTP::Request.new("POST", "/", headers, body)

          context = create_context(request)

          context.params["test"].should eq "test"
          context.params.json("address")["city"].should eq "New York"
        end

        it "parses json array" do
          headers = HTTP::Headers.new
          headers["Content-Type"] = "application/json"
          body = %(["test", "test2"])
          request = HTTP::Request.new("POST", "/", headers, body)

          context = create_context(request)

          context.params.json("_json").should eq %w(test test2)
        end
      end
    end
  end
end