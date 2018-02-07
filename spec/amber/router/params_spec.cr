require "../../../spec_helper"

module Amber::Router
  describe Parser do
    headers = HTTP::Headers.new

    context "when parsing query string" do
      it "returns query params" do
        request = HTTP::Request.new("GET", "/?test=test")
        request.params["test"].should eq "test"
      end

      it "returns array of values for same param key" do
        request = HTTP::Request.new("GET", "/?test=test&test=test2")
        request.params.fetch_all("test").size.should eq 2
        request.params.fetch_all("test").should eq %w(test test2)
      end
    end

    context "when parsing request body" do
      context "when content-type is form url urlencoded" do
        it "returns params" do
          headers["Content-Type"] = "application/x-www-form-urlencoded"
          body = "name=John Doe"
          request = HTTP::Request.new("POST", "/", headers, body)
          request.params["name"].should eq "John Doe"
        end

        it "parses body params with charset" do
          headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
          body = "\x68\x65\x6C\x6C\x6F\x3D\x77\x6F\x72\x6C\x64"
          request = HTTP::Request.new("POST", "/", headers, body)
          request.params["hello"].should eq "world"
        end
      end

      context "when parsing multipart" do
        it "parses files from multipart forms" do
          headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX"
          body = "--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"_csrf\"\r\n\r\nPcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\ntitle field\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"picture\"; filename=\"index.html\"\r\nContent-Type: text/html\r\n\r\n<head></head><body>Hello World!</body>\r\n\r\n--fhhRFLCazlkA0dX\r\nContent-Disposition: form-data; name=\"content\"\r\n\r\nseriously\r\n--fhhRFLCazlkA0dX--"

          request = HTTP::Request.new("POST", "/?test=example", headers, body)

          request.params.files["picture"].filename.should eq "index.html"
          request.params["title"].should eq "title field"
          request.params["_csrf"].should eq "PcCFp4oKJ1g-hZ-P7-phg0alC51pz7Pl12r0ZOncgxI"
        end
      end

      context "when parsing JSON body" do
        it "parses json hash" do
          headers["Content-Type"] = "application/json"
          body = %({ "test": "test", "address": { "city": "New York" }})
          request = HTTP::Request.new("POST", "/", headers, body)

          request.params["test"].should eq "test"
          request.params.json("address")["city"].should eq "New York"
        end

        it "parses json array" do
          headers["Content-Type"] = "application/json"
          body = %(["test", "test2"])
          request = HTTP::Request.new("POST", "/", headers, body)

          request.params.json("_json").should eq %w(test test2)
        end
      end

      context "when parsing route params" do
        it "parses params from route" do
          handler = ->(context : HTTP::Server::Context) {}
          route = Route.new("GET", "/fake/action/:id/:name", handler, :action, :web, "", "FakeController")
          Amber::Server.router.add(route)
          request = HTTP::Request.new("GET", "/fake/action/123/john")

          request.route

          request.params["id"].should eq "123"
          request.params["name"].should eq "john"
        end
      end
    end
  end
end
