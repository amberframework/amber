require "../../../spec_helper"

module Amber::Router
  describe HTTP::Request do
    headers = HTTP::Headers.new

    describe "#params" do
      context "when parsing query string" do
        it "returns array of values for same param key" do
          request = HTTP::Request.new("GET", "/?test=test&test=test2")
          request.params["test"].should eq "test"
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
            body = Bytes[104, 101, 108, 108, 111, 61, 119, 111, 114, 108, 100]
            request = HTTP::Request.new("POST", "/", headers, body)
            request.params["hello"].should eq "world"
          end
        end

        context "when parsing multipart" do
          it "parses files from multipart forms" do
            headers["Content-Type"] = "multipart/form-data; boundary=fhhRFLCazlkA0dX"
            multipart_content = ::File.read(::File.expand_path("spec/support/sample/multipart.txt"))
            multipart_body = multipart_content.gsub("\n", "\r\n")
            request = HTTP::Request.new("POST", "/?test=example", headers, multipart_body)

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
            request.params["id"].should eq "123"
            request.params["name"].should eq "john"
          end
        end
      end
    end

    describe "#method" do
      %w(PUT PATCH DELETE).each do |method|
        it "overrides form POST method to PUT, PATCH, DELETE" do
          headers[HTTP::Request::OVERRIDE_HEADER] = method
          request = HTTP::Request.new("POST", "/?test=test", headers)
          request.method.should eq method
        end

        it "overrides form GET method to PUT, PATCH, DELETE" do
          headers[HTTP::Request::OVERRIDE_HEADER] = method
          request = HTTP::Request.new("GET", "/?test=test", headers)
          request.method.should eq method
        end

        it "takes form post over header override" do
          headers[HTTP::Request::OVERRIDE_HEADER] = method
          headers["content-type"] = "application/x-www-form-urlencoded"
          request = HTTP::Request.new("GET", "/?test=test", headers, "_method=PATCH")
          request.method.should eq "PATCH"
        end
      end

      it "overrides form request method only by upper case value" do
        headers["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("GET", "/?test=test", headers, "_method=put")
        request.method.should eq "PUT"
      end
    end

    %w(PUT PATCH DELETE).each do |method|
      it "overrides form POST method to PUT, PATCH, DELETE" do
        headers["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("POST", "/?test=test", headers, "_method=#{method}")
        request.method.should eq method
      end

      it "overrides form GET method to PUT, PATCH, DELETE" do
        headers["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("GET", "/?test=test", headers, "_method=#{method}")
        request.method.should eq method
      end

      it "does not override other than PUT, PATCH, DELETE" do
        headers["content-type"] = "application/x-www-form-urlencoded"
        request = HTTP::Request.new("HEAD", "/?test=test", headers, "_method=#{method}")
        request.method.should eq "HEAD"
      end
    end
  end
end
