require "../../spec_helper"

private def loopback_networks : Array(Amber::Support::TrustedProxyNetwork)
  ["127.0.0.0/8", "::1"].map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
end

module Amber::Support
  describe TrustedProxies do
    describe "#trusts?" do
      it "trusts a peer inside a listed network" do
        trusted_proxies = TrustedProxies.new(loopback_networks, trusts_unix_socket_peers: false)
        trusted_proxies.trusts?(Socket::IPAddress.new("127.0.0.1", 0)).should be_true
        trusted_proxies.trusts?(Socket::IPAddress.new("203.0.113.9", 0)).should be_false
      end

      it "never trusts a missing peer" do
        TrustedProxies.new(loopback_networks, trusts_unix_socket_peers: true).trusts?(nil).should be_false
      end

      it "trusts a UNIX socket peer when the server listens on a UNIX socket" do
        trusted_proxies = TrustedProxies.new([] of TrustedProxyNetwork, trusts_unix_socket_peers: true)
        trusted_proxies.trusts?(Socket::UNIXAddress.new("/run/app.sock")).should be_true
      end

      it "does not trust a UNIX socket peer otherwise" do
        trusted_proxies = TrustedProxies.new(loopback_networks, trusts_unix_socket_peers: false)
        trusted_proxies.trusts?(Socket::UNIXAddress.new("/run/app.sock")).should be_false
      end
    end
  end
end
