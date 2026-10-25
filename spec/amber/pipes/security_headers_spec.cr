require "../../spec_helper"

private DEFAULT_HEADER_VALUES = {
  "X-Content-Type-Options"     => "nosniff",
  "X-Frame-Options"            => "DENY",
  "Content-Security-Policy"    => "frame-ancestors 'none'",
  "Referrer-Policy"            => "strict-origin-when-cross-origin",
  "Cross-Origin-Opener-Policy" => "same-origin",
}

# Runs *request* through *pipe* followed by a handler that writes a body,
# and returns the response headers as the client sees them.
private def headers_after(pipe : Amber::Pipe::SecurityHeaders, request : HTTP::Request, &on_reached : HTTP::Server::Context ->) : HTTP::Headers
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)
  pipe.next = ->(reached_context : HTTP::Server::Context) do
    on_reached.call(reached_context)
    reached_context.response.print "ok"
    nil
  end
  pipe.call(context)
  response.close
  io.rewind
  HTTP::Client::Response.from_io(io, decompress: false).headers
end

private def headers_after(pipe : Amber::Pipe::SecurityHeaders, request : HTTP::Request) : HTTP::Headers
  headers_after(pipe, request) { }
end

private def https_request : HTTP::Request
  HTTP::Request.new("GET", "/", HTTP::Headers{"HTTPS" => "on"})
end

module Amber
  module Pipe
    describe SecurityHeaders do
      describe "#call" do
        context "with the default settings" do
          it "sends every always-on header with its secure default" do
            headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))

            DEFAULT_HEADER_VALUES.each do |header_name, value|
              headers[header_name].should eq value
            end
            headers["Permissions-Policy"].should contain "camera=()"
          end

          it "reads Amber.settings.security_headers when no config is given" do
            original_value = Amber.settings.security_headers.referrer_policy
            begin
              Amber.settings.security_headers.referrer_policy = "same-origin"
              headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))
              headers["Referrer-Policy"].should eq "same-origin"
            ensure
              Amber.settings.security_headers.referrer_policy = original_value
            end
          end
        end

        context "with overridden settings" do
          it "sends the configured values" do
            config = Amber::Configuration::SecurityHeadersConfig.new
            config.frame_options = "SAMEORIGIN"
            config.content_security_policy = "frame-ancestors 'self'"

            headers = headers_after(SecurityHeaders.new(config), HTTP::Request.new("GET", "/"))

            headers["X-Frame-Options"].should eq "SAMEORIGIN"
            headers["Content-Security-Policy"].should eq "frame-ancestors 'self'"
            headers["X-Content-Type-Options"].should eq "nosniff"
          end

          it "leaves out a header whose value is empty" do
            config = Amber::Configuration::SecurityHeadersConfig.new
            config.permissions_policy = ""

            headers = headers_after(SecurityHeaders.new(config), HTTP::Request.new("GET", "/"))

            headers.has_key?("Permissions-Policy").should be_false
            headers["X-Frame-Options"].should eq "DENY"
          end
        end

        context "Strict-Transport-Security" do
          it "is sent on an HTTPS request" do
            headers = headers_after(SecurityHeaders.new, https_request)
            headers["Strict-Transport-Security"].should eq "max-age=63072000; includeSubDomains"
          end

          it "is sent on every request when Amber terminates TLS itself" do
            settings = Amber.settings
            original_key_file = settings.ssl_key_file
            original_cert_file = settings.ssl_cert_file
            begin
              settings.ssl_key_file = "config/ssl/server.key"
              settings.ssl_cert_file = "config/ssl/server.crt"
              headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))
              headers["Strict-Transport-Security"].should eq "max-age=63072000; includeSubDomains"
            ensure
              settings.ssl_key_file = original_key_file
              settings.ssl_cert_file = original_cert_file
            end
          end

          it "is not sent on a plain HTTP request" do
            headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))
            headers.has_key?("Strict-Transport-Security").should be_false
          end

          it "follows the same HTTPS decision as the cookie jar's Secure flag" do
            plain_request = HTTP::Request.new("GET", "/", HTTP::Headers{"HTTPS" => "off"})
            [plain_request, https_request].each do |request|
              headers = headers_after(SecurityHeaders.new, request)
              cookie_store = Amber::Router::Cookies::Store.build(request, "secret")
              secure_cookie = HTTP::Cookie.new("probe", "1", secure: true)
              cookie_jar_sends_secure_cookies = cookie_store.write_cookie?(secure_cookie)
              headers.has_key?("Strict-Transport-Security").should eq cookie_jar_sends_secure_cookies
            end
          end

          it "is not sent when its value is empty, even over HTTPS" do
            config = Amber::Configuration::SecurityHeadersConfig.new
            config.strict_transport_security = ""

            headers = headers_after(SecurityHeaders.new(config), https_request)

            headers.has_key?("Strict-Transport-Security").should be_false
          end
        end

        context "when the response already has one of these headers" do
          it "keeps a value an earlier pipe set" do
            io = IO::Memory.new
            response = HTTP::Server::Response.new(io)
            response.headers["X-Frame-Options"] = "SAMEORIGIN"
            response.headers["Strict-Transport-Security"] = "max-age=600"
            context = HTTP::Server::Context.new(https_request, response)
            pipe = SecurityHeaders.new
            pipe.next = ->(_context : HTTP::Server::Context) { nil }

            pipe.call(context)

            response.headers["X-Frame-Options"].should eq "SAMEORIGIN"
            response.headers.get("X-Frame-Options").size.should eq 1
            response.headers["Strict-Transport-Security"].should eq "max-age=600"
            response.headers["X-Content-Type-Options"].should eq "nosniff"
          end

          it "lets the controller replace a value" do
            headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/")) do |context|
              context.response.headers["Content-Security-Policy"] = "default-src 'self'"
            end

            headers.get("Content-Security-Policy").should eq ["default-src 'self'"]
          end
        end
      end

      context "plugged into a pipeline" do
        pipeline = Pipeline.new
        before_each do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end

          Amber::Server.router.draw :web do
            get "/securityheaders", HelloController, :index
          end

          pipeline.prepare_pipelines
        end

        it "adds the headers to a routed response" do
          request = HTTP::Request.new("GET", "/securityheaders")
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 200
          response.headers["X-Content-Type-Options"].should eq "nosniff"
          response.headers["X-Frame-Options"].should eq "DENY"
        end

        it "adds the headers to the 404 for a request that matches no route" do
          request = HTTP::Request.new("GET", "/securityheaders/no-such-route")
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 404
          DEFAULT_HEADER_VALUES.each do |header_name, value|
            response.headers[header_name].should eq value
          end
        end
      end

      context "in a pipeline that does not plug it" do
        it "adds nothing to the 404 for a request that matches no route" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug Amber::Pipe::Logger.new
          end
          pipeline.prepare_pipelines

          request = HTTP::Request.new("GET", "/securityheaders/no-such-route")
          response = create_request_and_return_io(pipeline, request)

          response.status_code.should eq 404
          response.headers.has_key?("X-Frame-Options").should be_false
        end
      end

      context "after the Error pipe" do
        it "keeps the headers on the 500 the Error pipe renders" do
          Amber::Server.router.draw :web do
            get "/", HelloController, :index
          end
          error_pipe = Error.new
          security_headers = SecurityHeaders.new
          error_pipe.next = security_headers
          security_headers.next = ->(_context : HTTP::Server::Context) { raise "Oops!" }

          response = create_request_and_return_io(error_pipe, HTTP::Request.new("GET", "/"))

          response.status_code.should eq 500
          response.headers["X-Frame-Options"].should eq "DENY"
          response.headers["X-Content-Type-Options"].should eq "nosniff"
        end
      end
    end
  end
end
