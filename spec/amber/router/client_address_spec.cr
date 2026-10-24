require "../../spec_helper"

private def networks(*notations : String) : Array(Amber::Support::TrustedProxyNetwork)
  notations.to_a.map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
end

private def loopback_only : Amber::Support::TrustedProxies
  Amber::Support::TrustedProxies.new(networks("127.0.0.0/8", "::1"), trusts_unix_socket_peers: false)
end

private def request_from(peer : Socket::Address?, headers : HTTP::Headers = HTTP::Headers.new) : HTTP::Request
  request = HTTP::Request.new("GET", "/", headers)
  request.remote_address = peer
  request
end

private def ip(address : String) : Socket::IPAddress
  Socket::IPAddress.new(address, 54_321)
end

private def client_address_of(request : HTTP::Request,
                              trusted_proxies : Amber::Support::TrustedProxies = loopback_only,
                              list_of_header_names : Array(String)? = nil) : String?
  Amber::Router::ClientAddress.resolve(request, trusted_proxies, list_of_header_names).try(&.address)
end

module Amber::Router
  describe ClientAddress do
    describe ".resolve" do
      context "with an untrusted peer" do
        it "returns the peer and ignores X-Forwarded-For" do
          request = request_from(ip("203.0.113.9"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.1"})
          client_address_of(request).should eq "203.0.113.9"
        end

        it "returns the peer and ignores Forwarded" do
          request = request_from(ip("203.0.113.9"), HTTP::Headers{"Forwarded" => "for=198.51.100.1"})
          client_address_of(request).should eq "203.0.113.9"
        end

        it "returns nil for a request with no peer" do
          request = request_from(nil, HTTP::Headers{"X-Forwarded-For" => "198.51.100.1"})
          client_address_of(request).should be_nil
        end
      end

      context "with a trusted proxy" do
        it "returns the address the proxy appended" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.7"})
          client_address_of(request).should eq "198.51.100.7"
        end

        it "returns the peer when no forwarding header is present" do
          client_address_of(request_from(ip("127.0.0.1"))).should eq "127.0.0.1"
        end

        it "ignores a spoofed leftmost entry" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "1.1.1.1, 198.51.100.7"})
          client_address_of(request).should eq "198.51.100.7"
        end

        it "skips several trusted hops" do
          trusted_proxies = Amber::Support::TrustedProxies.new(networks("127.0.0.0/8", "10.0.0.0/8"), trusts_unix_socket_peers: false)
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "6.6.6.6, 198.51.100.7, 10.0.0.3, 10.0.0.2"})
          client_address_of(request, trusted_proxies).should eq "198.51.100.7"
        end

        it "returns the farthest hop when every hop is trusted" do
          trusted_proxies = Amber::Support::TrustedProxies.new(networks("127.0.0.0/8", "10.0.0.0/8"), trusts_unix_socket_peers: false)
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "10.0.0.9, 10.0.0.2"})
          client_address_of(request, trusted_proxies).should eq "10.0.0.9"
        end

        it "reads several X-Forwarded-For header lines in order" do
          headers = HTTP::Headers.new
          headers.add("X-Forwarded-For", "1.1.1.1")
          headers.add("X-Forwarded-For", "198.51.100.7")
          client_address_of(request_from(ip("127.0.0.1"), headers)).should eq "198.51.100.7"
        end

        it "handles IPv6 peers and hops" do
          request = request_from(ip("::1"), HTTP::Headers{"X-Forwarded-For" => "2001:db8::bad, 2001:db8::7"})
          client_address_of(request).should eq "2001:db8::7"
        end

        it "strips a port from an IPv4 hop" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.7:4711"})
          client_address_of(request).should eq "198.51.100.7"
        end

        it "stops at a malformed hop and returns the nearest verified address" do
          trusted_proxies = Amber::Support::TrustedProxies.new(networks("127.0.0.0/8", "10.0.0.0/8"), trusts_unix_socket_peers: false)
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.7, not-an-ip, 10.0.0.2"})
          client_address_of(request, trusted_proxies).should eq "10.0.0.2"
        end

        it "returns the peer when the only hop is malformed" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "999.1.1.1"})
          client_address_of(request).should eq "127.0.0.1"
        end
      end

      context "with the Forwarded header" do
        it "reads for= from the right" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"Forwarded" => "for=1.1.1.1, for=198.51.100.7;proto=https"})
          client_address_of(request).should eq "198.51.100.7"
        end

        it "reads a quoted, bracketed IPv6 node with a port" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"Forwarded" => %(for="[2001:db8:cafe::17]:4711")})
          client_address_of(request).should eq "2001:db8:cafe::17"
        end

        it "takes Forwarded over X-Forwarded-For" do
          headers = HTTP::Headers{"Forwarded" => "for=198.51.100.7", "X-Forwarded-For" => "203.0.113.50"}
          client_address_of(request_from(ip("127.0.0.1"), headers)).should eq "198.51.100.7"
        end

        it "treats an obfuscated or unknown node as malformed" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"Forwarded" => "for=198.51.100.7, for=unknown"})
          client_address_of(request).should eq "127.0.0.1"
        end

        it "treats an element without for= as malformed" do
          request = request_from(ip("127.0.0.1"), HTTP::Headers{"Forwarded" => "for=198.51.100.7, proto=https"})
          client_address_of(request).should eq "127.0.0.1"
        end
      end

      context "with named headers" do
        it "reads the first named header that is present, from a trusted proxy" do
          headers = HTTP::Headers{"X-Forwarded-For" => "1.1.1.1", "CF-Connecting-IP" => "198.51.100.7"}
          request = request_from(ip("127.0.0.1"), headers)
          client_address_of(request, list_of_header_names: ["X-Unmatched", "CF-Connecting-IP"]).should eq "198.51.100.7"
        end

        it "ignores the named header from an untrusted peer" do
          request = request_from(ip("203.0.113.9"), HTTP::Headers{"CF-Connecting-IP" => "198.51.100.7"})
          client_address_of(request, list_of_header_names: ["CF-Connecting-IP"]).should eq "203.0.113.9"
        end
      end

      context "with a UNIX socket peer" do
        it "reads the forwarded chain when the server listens on a UNIX socket" do
          trusted_proxies = Amber::Support::TrustedProxies.new(networks("127.0.0.0/8"), trusts_unix_socket_peers: true)
          request = request_from(Socket::UNIXAddress.new("/run/app.sock"), HTTP::Headers{"X-Forwarded-For" => "1.1.1.1, 198.51.100.7"})
          client_address_of(request, trusted_proxies).should eq "198.51.100.7"
        end

        it "returns nil when the UNIX socket peer is not trusted" do
          request = request_from(Socket::UNIXAddress.new("/run/app.sock"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.7"})
          client_address_of(request).should be_nil
        end
      end
    end
  end
end

describe HTTP::Request do
  describe "#client_ip" do
    it "uses the application's trusted proxy setting" do
      trusted = request_from(ip("127.0.0.1"), HTTP::Headers{"X-Forwarded-For" => "1.1.1.1, 198.51.100.7"})
      spoofed = request_from(ip("203.0.113.9"), HTTP::Headers{"X-Forwarded-For" => "198.51.100.7"})

      trusted.client_ip.try(&.address).should eq "198.51.100.7"
      spoofed.client_ip.try(&.address).should eq "203.0.113.9"
    end
  end
end

describe "A proxy on a UNIX socket" do
  it "is trusted for the scheme and client address when the server listens on that socket" do
    server_config = Amber.settings.server
    socket_path = File.tempname("amber-trusted-proxy", ".sock")
    server = HTTP::Server.new do |context|
      request = context.request
      context.cookies.encrypted.set("amber.session", "session-id", http_only: true, secure: true)
      context.cookies.write(context.response.headers)
      context.response.print "#{request.scheme} #{request.client_ip.try(&.address)}"
    end
    server.bind_unix(socket_path)
    spawn(name: "unix socket proxy spec server") { server.listen }

    begin
      server_config.unix_socket = socket_path
      forwarded_headers = HTTP::Headers{"X-Forwarded-Proto" => "https", "X-Forwarded-For" => "1.1.1.1, 198.51.100.7"}
      response = HTTP::Client.new(UNIXSocket.new(socket_path)).get("/login", headers: forwarded_headers)
      response.body.should eq "https 198.51.100.7"
      response.headers["Set-Cookie"].should contain "Secure"

      server_config.unix_socket = nil
      untrusted = HTTP::Client.new(UNIXSocket.new(socket_path)).get("/login", headers: forwarded_headers)
      untrusted.body.should eq "http "
      untrusted.headers.get?("Set-Cookie").should be_nil
    ensure
      server_config.unix_socket = nil
      server.close
      File.delete?(socket_path)
    end
  end
end
