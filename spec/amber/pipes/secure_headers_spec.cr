require "../../spec_helper"

module Amber::Pipe
  describe SecureHeaders do
    it "adds default security headers to the response (HSTS disabled by default)" do
      request = HTTP::Request.new("GET", "/")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      pipe = SecureHeaders.new
      pipe.next = HTTP::Handler::HandlerProc.new { |_ctx| }

      pipe.call(context)

      context.response.headers["X-Content-Type-Options"].should eq "nosniff"
      context.response.headers["X-XSS-Protection"].should eq "1; mode=block"
      context.response.headers["X-Frame-Options"].should eq "SAMEORIGIN"
      context.response.headers["Referrer-Policy"].should eq "strict-origin-when-cross-origin"
      context.response.headers.has_key?("Strict-Transport-Security").should be_false
    end

    it "adds HSTS when enabled" do
      request = HTTP::Request.new("GET", "/")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)

      pipe = SecureHeaders.new(hsts: true)
      pipe.next = HTTP::Handler::HandlerProc.new { |_ctx| }

      pipe.call(context)

      context.response.headers["Strict-Transport-Security"].should eq "max-age=31536000; includeSubDomains"
    end

    it "keeps security headers on 404 responses when plugged above the Error pipe" do
      # Regression guard for the template pipeline order: Error handles
      # RouteNotFound without calling further pipes, so SecureHeaders must run
      # before Error or 404/403 responses go out without any security headers.
      request = HTTP::Request.new("GET", "/route-that-does-not-exist")
      request.headers["Accept"] = "text/html"

      pipe = SecureHeaders.new
      pipe.next = Error.new

      response = create_request_and_return_io(pipe, request)

      response.status_code.should eq 404
      response.headers["X-Content-Type-Options"].should eq "nosniff"
    end
  end
end
