require "../../spec_helper"

private LOOPBACK_ONLY = Amber::Configuration::ServerConfig::DEFAULT_TRUSTED_PROXIES.map do |notation|
  Amber::Support::TrustedProxyNetwork.parse(notation)
end

private def request_from(peer : String?, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Request
  request = HTTP::Request.new("GET", "/login", headers)
  request.remote_address = Socket::IPAddress.new(peer, 54_321) if peer
  request
end

private def scheme_of(request : HTTP::Request,
                      list_of_trusted_proxies = LOOPBACK_ONLY,
                      server_terminates_tls : Bool = false) : String
  Amber::Router::RequestScheme.resolve(request, list_of_trusted_proxies, server_terminates_tls)
end

module Amber::Router
  describe RequestScheme do
    describe ".resolve" do
      context "with a trusted loopback proxy" do
        it "honors X-Forwarded-Proto: https" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request).should eq "https"
        end

        it "honors an IPv6 loopback peer" do
          request = request_from("::1", HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request).should eq "https"
        end

        it "honors X-Forwarded-Proto: http" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "http"})
          scheme_of(request, server_terminates_tls: true).should eq "http"
        end

        it "keeps the connection scheme when no forwarding header is present" do
          scheme_of(request_from("127.0.0.1")).should eq "http"
        end

        it "ignores a forwarded value that is not http or https" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "gopher"})
          scheme_of(request).should eq "http"
        end

        it "honors the CGI-style HTTPS: on header" do
          request = request_from("127.0.0.1", HTTP::Headers{"HTTPS" => "on"})
          scheme_of(request).should eq "https"
        end
      end

      context "with an untrusted peer" do
        it "keeps the real scheme when the client spoofs X-Forwarded-Proto" do
          request = request_from("203.0.113.9", HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request).should eq "http"
        end

        it "keeps the real scheme when the client spoofs Forwarded" do
          request = request_from("203.0.113.9", HTTP::Headers{"Forwarded" => "proto=https"})
          scheme_of(request).should eq "http"
        end

        it "keeps the real scheme when the client spoofs HTTPS: on" do
          request = request_from("203.0.113.9", HTTP::Headers{"HTTPS" => "on"})
          scheme_of(request).should eq "http"
        end

        it "cannot downgrade a connection Amber accepted over TLS" do
          request = request_from("203.0.113.9", HTTP::Headers{"X-Forwarded-Proto" => "http"})
          scheme_of(request, server_terminates_tls: true).should eq "https"
        end

        it "treats a request with no peer address as untrusted" do
          request = request_from(nil, HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request).should eq "http"
        end
      end

      context "with the RFC 7239 Forwarded header" do
        it "reads proto from a trusted proxy" do
          request = request_from("127.0.0.1", HTTP::Headers{"Forwarded" => "for=198.51.100.7;proto=https;host=example.com"})
          scheme_of(request).should eq "https"
        end

        it "reads a quoted, mixed-case proto parameter" do
          request = request_from("127.0.0.1", HTTP::Headers{"Forwarded" => %(for="[2001:db8::7]:4711";Proto="HTTPS")})
          scheme_of(request).should eq "https"
        end

        it "takes Forwarded over X-Forwarded-Proto" do
          headers = HTTP::Headers{"Forwarded" => "proto=https", "X-Forwarded-Proto" => "http"}
          scheme_of(request_from("127.0.0.1", headers)).should eq "https"
        end

        it "falls back to X-Forwarded-Proto when the last element has no proto" do
          headers = HTTP::Headers{"Forwarded" => "for=198.51.100.7", "X-Forwarded-Proto" => "https"}
          scheme_of(request_from("127.0.0.1", headers)).should eq "https"
        end

        it "keeps commas inside quoted values within one element" do
          request = request_from("127.0.0.1", HTTP::Headers{"Forwarded" => %(for="a,b";proto=https)})
          scheme_of(request).should eq "https"
        end
      end

      context "with a chain of proxies" do
        it "takes the X-Forwarded-Proto value the trusted hop appended last" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "http, https"})
          scheme_of(request).should eq "https"
        end

        it "ignores an https value a client placed earlier in the chain" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "https, http"})
          scheme_of(request).should eq "http"
        end

        it "reads the last of several X-Forwarded-Proto header lines" do
          headers = HTTP::Headers.new
          headers.add("X-Forwarded-Proto", "http")
          headers.add("X-Forwarded-Proto", "https")
          scheme_of(request_from("127.0.0.1", headers)).should eq "https"
        end

        it "takes the proto of the last Forwarded element" do
          request = request_from("127.0.0.1", HTTP::Headers{"Forwarded" => "for=192.0.2.60;proto=http, for=10.0.0.4;proto=https"})
          scheme_of(request).should eq "https"
        end

        it "trusts a platform load balancer once its network is listed" do
          list_of_trusted_proxies = ["127.0.0.0/8", "10.0.0.0/8"].map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
          request = request_from("10.244.0.17", HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request, list_of_trusted_proxies).should eq "https"
          scheme_of(request).should eq "http"
        end

        it "trusts nobody when the list is empty" do
          request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "https"})
          scheme_of(request, [] of Amber::Support::TrustedProxyNetwork).should eq "http"
        end
      end
    end
  end
end

describe HTTP::Request do
  describe "#https?" do
    it "uses the application's trusted proxy setting" do
      trusted = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "https"})
      spoofed = request_from("203.0.113.9", HTTP::Headers{"X-Forwarded-Proto" => "https"})

      trusted.https?.should be_true
      trusted.scheme.should eq "https"
      spoofed.https?.should be_false
      spoofed.scheme.should eq "http"
    end
  end
end

describe Amber::Router::Cookies::Store do
  describe ".build" do
    it "emits a Secure session cookie behind a trusted TLS-terminating proxy" do
      request = request_from("127.0.0.1", HTTP::Headers{"X-Forwarded-Proto" => "https"})
      cookies = Amber::Router::Cookies::Store.build(request, "a" * 32)
      cookies.encrypted.set("amber.session", "session-id", http_only: true, secure: true)

      response_headers = HTTP::Headers.new
      cookies.write(response_headers)

      set_cookie_lines = response_headers.get?("Set-Cookie") || [] of String
      set_cookie_lines.size.should eq 1
      set_cookie_lines.first.should start_with "amber.session="
      set_cookie_lines.first.should contain "Secure"
    end

    it "emits a Secure session cookie when the proxy sends Forwarded" do
      request = request_from("127.0.0.1", HTTP::Headers{"Forwarded" => "for=198.51.100.7;proto=https"})
      cookies = Amber::Router::Cookies::Store.build(request, "a" * 32)
      cookies.encrypted.set("amber.session", "session-id", http_only: true, secure: true)

      response_headers = HTTP::Headers.new
      cookies.write(response_headers)

      (response_headers.get?("Set-Cookie") || [] of String).size.should eq 1
    end

    it "withholds a Secure cookie from a spoofed header on plain HTTP" do
      request = request_from("203.0.113.9", HTTP::Headers{"X-Forwarded-Proto" => "https"})
      cookies = Amber::Router::Cookies::Store.build(request, "a" * 32)
      cookies.encrypted.set("amber.session", "session-id", http_only: true, secure: true)

      response_headers = HTTP::Headers.new
      cookies.write(response_headers)

      (response_headers.get?("Set-Cookie") || [] of String).should be_empty
    end
  end
end

describe "A session cookie over a real loopback connection" do
  it "arrives when a trusted proxy reports https and is withheld otherwise" do
    server = HTTP::Server.new do |context|
      context.cookies.encrypted.set("amber.session", "session-id", http_only: true, secure: true)
      context.cookies.write(context.response.headers)
      context.response.print "ok"
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn(name: "trusted proxy spec server") { server.listen }

    begin
      client = HTTP::Client.new(address.address, address.port)
      forwarded_https = client.get("/login", headers: HTTP::Headers{"X-Forwarded-Proto" => "https"})
      plain = client.get("/login")

      forwarded_https.headers.get?("Set-Cookie").should_not be_nil
      forwarded_https.headers["Set-Cookie"].should contain "Secure"
      plain.headers.get?("Set-Cookie").should be_nil
    ensure
      server.close
    end
  end
end
