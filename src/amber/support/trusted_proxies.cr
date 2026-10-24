require "./trusted_proxy_network"

module Amber::Support
  # The set of peers Amber believes when they forward a client's scheme or
  # address: the parsed `server.trusted_proxies` networks, plus every UNIX
  # socket peer when Amber itself listens on a UNIX socket
  # (`server.unix_socket`). A UNIX socket connection is local by construction,
  # and the socket file's permissions decide who may open it, so a proxy that
  # reaches Amber that way is as trustworthy as one on loopback.
  #
  # ```
  # networks = ["127.0.0.0/8"].map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
  # trusted_proxies = Amber::Support::TrustedProxies.new(networks, trusts_unix_socket_peers: false)
  # trusted_proxies.trusts?(Socket::IPAddress.new("127.0.0.1", 0)) # => true
  # ```
  struct TrustedProxies
    getter list_of_networks : Array(TrustedProxyNetwork)
    getter? trusts_unix_socket_peers : Bool

    def initialize(@list_of_networks : Array(TrustedProxyNetwork), *, @trusts_unix_socket_peers : Bool)
    end

    # Returns `true` when *peer* is a trusted proxy. A request without a peer
    # address (built in memory rather than read from a socket) never is.
    def trusts?(peer : Socket::Address?) : Bool
      return false unless peer
      return trusts_unix_socket_peers? if peer.is_a?(Socket::UNIXAddress)

      list_of_networks.any?(&.includes?(peer))
    end
  end
end
