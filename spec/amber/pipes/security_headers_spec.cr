require "../../spec_helper"
require "file_utils"

private DEFAULT_HEADER_VALUES = {
  "X-Content-Type-Options"  => "nosniff",
  "X-Frame-Options"         => "DENY",
  "Content-Security-Policy" => "frame-ancestors 'none'",
  "Referrer-Policy"         => "strict-origin-when-cross-origin",
}

# Sends a WebSocket handshake for *path* with *version* and returns the
# response's status line and headers as the client reads them. *upgrade*
# is the `Upgrade` header's value; *sends_key* leaves `Sec-WebSocket-Key`
# out when `false`.
private def handshake_response_head(port : Int32, path : String, version : String, upgrade : String = "websocket", sends_key : Bool = true, extra_header : String? = nil) : String
  socket = TCPSocket.new("127.0.0.1", port)
  socket << "GET #{path} HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: #{upgrade}\r\nConnection: Upgrade\r\n"
  socket << extra_header << "\r\n" if extra_header
  socket << "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" if sends_key
  socket << "Sec-WebSocket-Version: #{version}\r\n\r\n"
  socket.flush
  head = String.build do |builder|
    while line = socket.gets(chomp: false)
      break if line == "\r\n"
      builder << line
    end
  end
  socket.close
  head
end

# Serves *pipeline* on a loopback port for the block.
private def serving(pipeline : Amber::Pipe::Pipeline, &)
  server = HTTP::Server.new(pipeline)
  address = server.bind_tcp("127.0.0.1", 0)
  spawn(name: "security headers websocket spec server") { server.listen }
  begin
    yield address.port
  ensure
    server.close
  end
end

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

# A request that a TLS-terminating proxy on loopback, which the default
# `server.trusted_proxies` trusts, forwarded with `X-Forwarded-Proto: https`.
private def https_request : HTTP::Request
  request = HTTP::Request.new("GET", "/", HTTP::Headers{"X-Forwarded-Proto" => "https"})
  request.remote_address = Socket::IPAddress.new("127.0.0.1", 54_321)
  request
end

# The same claim, plus `HTTPS: on`, from a peer that is not a trusted proxy.
private def spoofed_https_request : HTTP::Request
  request = HTTP::Request.new("GET", "/", HTTP::Headers{"X-Forwarded-Proto" => "https", "HTTPS" => "on"})
  request.remote_address = Socket::IPAddress.new("203.0.113.9", 54_321)
  request
end

# Sends the start of a response, then raises an Amber error, the way a
# streaming action fails partway through.
private class StreamThenForbid < Amber::Pipe::Base
  def call(context : HTTP::Server::Context)
    context.response.print "partial"
    context.response.flush
    raise Amber::Exceptions::Forbidden.new("stopped after the response started")
  end
end

# A constraint that counts how often it is asked, the way a constraint that
# consumes a one-time handshake token would notice a second check.
private class CountingConstraint
  include Amber::Router::Constraint

  getter number_of_checks : Int32 = 0

  def matches?(request : HTTP::Request) : Bool
    @number_of_checks += 1
    true
  end
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
            headers.has_key?("Permissions-Policy").should be_false
            headers.has_key?("Cross-Origin-Opener-Policy").should be_false
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
            config.referrer_policy = ""

            headers = headers_after(SecurityHeaders.new(config), HTTP::Request.new("GET", "/"))

            headers.has_key?("Referrer-Policy").should be_false
            headers["X-Frame-Options"].should eq "DENY"
          end

          it "sends the opt-in headers once they have values" do
            config = Amber::Configuration::SecurityHeadersConfig.new
            config.permissions_policy = "camera=()"
            config.cross_origin_opener_policy = "same-origin"

            headers = headers_after(SecurityHeaders.new(config), HTTP::Request.new("GET", "/"))

            headers["Permissions-Policy"].should eq "camera=()"
            headers["Cross-Origin-Opener-Policy"].should eq "same-origin"
          end
        end

        context "Strict-Transport-Security" do
          it "is sent on an HTTPS request" do
            headers = headers_after(SecurityHeaders.new, https_request)
            headers["Strict-Transport-Security"].should eq "max-age=63072000"
          end

          it "is sent on every request when Amber terminates TLS itself" do
            settings = Amber.settings
            original_key_file = settings.ssl_key_file
            original_cert_file = settings.ssl_cert_file
            begin
              settings.ssl_key_file = "config/ssl/server.key"
              settings.ssl_cert_file = "config/ssl/server.crt"
              headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))
              headers["Strict-Transport-Security"].should eq "max-age=63072000"
            ensure
              settings.ssl_key_file = original_key_file
              settings.ssl_cert_file = original_cert_file
            end
          end

          it "is not sent on a plain HTTP request" do
            headers = headers_after(SecurityHeaders.new, HTTP::Request.new("GET", "/"))
            headers.has_key?("Strict-Transport-Security").should be_false
          end

          it "is not sent when an untrusted peer claims HTTPS" do
            headers = headers_after(SecurityHeaders.new, spoofed_https_request)
            headers.has_key?("Strict-Transport-Security").should be_false
          end

          it "follows the same HTTPS decision as the cookie jar's Secure flag" do
            plain_request = HTTP::Request.new("GET", "/", HTTP::Headers{"HTTPS" => "off"})
            [plain_request, https_request, spoofed_https_request].each do |request|
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

      context "when the matched route's constraint fails" do
        it "uses the SecurityHeaders pipe of that route's pipeline" do
          web_config = Amber::Configuration::SecurityHeadersConfig.new
          web_config.frame_options = "SAMEORIGIN"
          api_config = Amber::Configuration::SecurityHeadersConfig.new
          api_config.referrer_policy = "no-referrer"

          pipeline = Pipeline.new
          pipeline.build :securityheaders_web do
            plug SecurityHeaders.new(web_config)
          end
          pipeline.build :securityheaders_api do
            plug SecurityHeaders.new(api_config)
          end
          Amber::Server.router.draw :securityheaders_api do
            constraint Amber::Router::Constraints::Header.new("X-SecurityHeaders-Spec", "yes") do
              get "/securityheaders-constrained", HelloController, :index
            end
          end
          pipeline.prepare_pipelines

          response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/securityheaders-constrained"))

          response.status_code.should eq 404
          response.headers["X-Frame-Options"].should eq "DENY"
          response.headers["Referrer-Policy"].should eq "no-referrer"
        end
      end

      context "for a request that matches no route" do
        it "uses the application-wide settings, not one pipeline's own config" do
          web_config = Amber::Configuration::SecurityHeadersConfig.new
          web_config.frame_options = "SAMEORIGIN"
          pipeline = Pipeline.new
          pipeline.build :securityheaders_web do
            plug SecurityHeaders.new(web_config)
          end
          pipeline.prepare_pipelines

          response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/securityheaders/unrouted-app-wide"))

          response.status_code.should eq 404
          response.headers["X-Frame-Options"].should eq Amber.settings.security_headers.frame_options
        end
      end

      context "for a WebSocket handshake" do
        it "adds the application-wide headers to the 101 response and to the 426 for an unsupported version" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            accepted = handshake_response_head(port, "/securityheaders-socket", version: "13")
            accepted.should start_with "HTTP/1.1 101"
            accepted.should contain "X-Frame-Options: DENY"
            accepted.should contain "X-Content-Type-Options: nosniff"

            refused = handshake_response_head(port, "/securityheaders-socket", version: "8")
            refused.should start_with "HTTP/1.1 426"
            refused.should contain "X-Frame-Options: DENY"
          end
        end

        it "accepts an Upgrade header in any letter case" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket-case", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            accepted = handshake_response_head(port, "/securityheaders-socket-case", version: "13", upgrade: "WebSocket")
            accepted.should start_with "HTTP/1.1 101"
            accepted.should contain "X-Frame-Options: DENY"
          end
        end

        it "keeps the headers on the 400 for a handshake without a Sec-WebSocket-Key" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket-keyless", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            refused = handshake_response_head(port, "/securityheaders-socket-keyless", version: "13", sends_key: false)
            refused.should start_with "HTTP/1.1 400"
            refused.should contain "X-Frame-Options: DENY"
            refused.should contain "X-Content-Type-Options: nosniff"
          end
        end

        it "uses the application-wide settings when an HTTP route without the pipe also matches the path" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket-shared", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.build :securityheaders_bare do
            plug Amber::Pipe::Logger.new
          end
          Amber::Server.router.draw :securityheaders_bare do
            get "/securityheaders-socket-shared", HelloController, :index
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            accepted = handshake_response_head(port, "/securityheaders-socket-shared", version: "13")
            accepted.should start_with "HTTP/1.1 101"
            accepted.should contain "X-Frame-Options: DENY"
          end
        end

        it "holds a handshake to the constraint of an HTTP route on the same path" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket-guarded", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.build :securityheaders_guarded do
            plug Amber::Pipe::Logger.new
          end
          Amber::Server.router.draw :securityheaders_guarded do
            constraint Amber::Router::Constraints::Header.new("X-SecurityHeaders-Spec", "yes") do
              get "/securityheaders-socket-guarded", HelloController, :index
            end
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            refused = handshake_response_head(port, "/securityheaders-socket-guarded", version: "13")
            refused.should start_with "HTTP/1.1 404"
            refused.should contain "X-Frame-Options: DENY"
          end
        end

        it "holds a socket-only handshake to the constraint block it was declared in" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          Amber::Server.router.draw :web do
            constraint Amber::Router::Constraints::Header.new("X-SecurityHeaders-Spec", "yes") do
              websocket "/securityheaders-socket-declared-guarded", UserSocket
            end
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            refused = handshake_response_head(port, "/securityheaders-socket-declared-guarded", version: "13")
            refused.should start_with "HTTP/1.1 404"
            refused.should contain "X-Frame-Options: DENY"

            accepted = handshake_response_head(port, "/securityheaders-socket-declared-guarded", version: "13", extra_header: "X-SecurityHeaders-Spec: yes")
            accepted.should start_with "HTTP/1.1 101"
          end
        end

        it "lets a socket in its own constraint block skip the constraint of an HTTP route on the path" do
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.build :securityheaders_tenants do
            plug Amber::Pipe::Logger.new
          end
          Amber::Server.router.draw :securityheaders_tenants do
            constraint Amber::Router::Constraints::Header.new("X-SecurityHeaders-Tenant", "a") do
              get "/securityheaders-tenant-socket", HelloController, :index
              websocket "/securityheaders-tenant-socket", UserSocket
            end
            constraint Amber::Router::Constraints::Header.new("X-SecurityHeaders-Tenant", "b") do
              websocket "/securityheaders-tenant-socket", UserSocket
            end
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            tenant_b = handshake_response_head(port, "/securityheaders-tenant-socket", version: "13", extra_header: "X-SecurityHeaders-Tenant: b")
            tenant_b.should start_with "HTTP/1.1 101"

            tenant_c = handshake_response_head(port, "/securityheaders-tenant-socket", version: "13", extra_header: "X-SecurityHeaders-Tenant: c")
            tenant_c.should start_with "HTTP/1.1 404"
          end
        end

        it "checks a socket route's constraint once per handshake" do
          counting_constraint = CountingConstraint.new
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          Amber::Server.router.draw :web do
            constraint counting_constraint do
              websocket "/securityheaders-socket-counted", UserSocket
            end
          end
          pipeline.prepare_pipelines

          serving(pipeline) do |port|
            handshake_response_head(port, "/securityheaders-socket-counted", version: "13").should start_with "HTTP/1.1 101"
          end
          counting_constraint.number_of_checks.should eq 1
        end

        it "answers a plain request for a socket-only path with a 404 that carries the headers" do
          Amber::WebSockets::Server.create_endpoint("/securityheaders-socket-only", UserSocket)
          pipeline = Pipeline.new
          pipeline.build :web do
            plug SecurityHeaders.new
          end
          pipeline.prepare_pipelines

          response = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/securityheaders-socket-only"))

          response.status_code.should eq 404
          response.headers["X-Frame-Options"].should eq "DENY"
        end
      end

      context "when an error escapes after the response has started" do
        it "re-raises it instead of rewriting a status line already sent" do
          pipeline = Pipeline.new
          pipeline.build :securityheaders_streaming do
            plug SecurityHeaders.new
            plug StreamThenForbid.new
          end
          Amber::Server.router.draw :securityheaders_streaming do
            get "/securityheaders-streaming", HelloController, :index
          end
          pipeline.prepare_pipelines

          io = IO::Memory.new
          response = HTTP::Server::Response.new(io)
          context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/securityheaders-streaming"), response)

          expect_raises(Amber::Exceptions::Forbidden) { pipeline.call(context) }
          io.to_s.scan("HTTP/1.1 ").size.should eq 1
          io.to_s.should start_with "HTTP/1.1 200"
        end

        it "is raised again by the Error pipe in the documented order" do
          pipeline = Pipeline.new
          pipeline.build :securityheaders_streaming_error do
            plug Error.new
            plug SecurityHeaders.new
            plug StreamThenForbid.new
          end
          Amber::Server.router.draw :securityheaders_streaming_error do
            get "/securityheaders-streaming-error", HelloController, :index
          end
          pipeline.prepare_pipelines

          io = IO::Memory.new
          response = HTTP::Server::Response.new(io)
          context = HTTP::Server::Context.new(HTTP::Request.new("GET", "/securityheaders-streaming-error"), response)

          expect_raises(Amber::Exceptions::Forbidden) { pipeline.call(context) }
          io.to_s.scan("HTTP/1.1 ").size.should eq 1
        end
      end

      context "in a static pipeline" do
        it "adds the headers to a served file and to the 404 for a missing asset" do
          public_dir = File.tempname("amber-securityheaders-public")
          Dir.mkdir_p(File.join(public_dir, "securityheaders-static"))
          File.write(File.join(public_dir, "securityheaders-static", "app.css"), "body {}")
          begin
            pipeline = Pipeline.new
            pipeline.build :securityheaders_static do
              plug Error.new
              plug SecurityHeaders.new
              plug Static.new(public_dir)
            end
            Amber::Server.router.draw :securityheaders_static do
              get "/securityheaders-static/*", Amber::Controller::Static, :index
            end
            pipeline.prepare_pipelines

            served = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/securityheaders-static/app.css"))
            served.status_code.should eq 200
            served.headers["X-Frame-Options"].should eq "DENY"
            served.headers["X-Content-Type-Options"].should eq "nosniff"

            missing = create_request_and_return_io(pipeline, HTTP::Request.new("GET", "/securityheaders-static/missing.css"))
            missing.status_code.should eq 404
            missing.headers["X-Frame-Options"].should eq "DENY"
          ensure
            FileUtils.rm_rf(public_dir)
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
