require "../../spec_helper"

module Amber
  module Pipe
    describe Error do
      it "returns status code 404 when route not found" do
        router = Error.new
        request = HTTP::Request.new("GET", "/")

        response = create_request_and_return_io(router, request)

        response.status_code.should eq 404
      end

      it "returns status code 500 for all other exceptions" do
        error = Error.new
        error.next = ->(_context : HTTP::Server::Context) { raise "Oops!" }
        request = HTTP::Request.new("GET", "/")

        Amber::Server.router.draw :web do
          get "/", HelloController, :index
        end

        response = create_request_and_return_io(error, request)

        response.status_code.should eq 500
      end

      it "escapes exception messages in the HTML response body" do
        error = Error.new
        error.next = ->(_context : HTTP::Server::Context) { raise "<script>alert('xss')</script>" }
        request = HTTP::Request.new("GET", "/")
        request.headers["Accept"] = "text/html"

        response = create_request_and_return_io(error, request)

        response.status_code.should eq 500
        response.body.should contain("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")
        response.body.should_not contain("<script>")
      end
    end
  end
end
