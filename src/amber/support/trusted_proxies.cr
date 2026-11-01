require "./trusted_proxy_network"

module Amber::Support
  # The set of peers Amber believes when they forward a client's scheme or
  # address, and the one header family those peers write.
  #
  # The peers are the parsed `server.trusted_proxies` networks, plus every
  # UNIX socket peer when Amber itself listens on a UNIX socket
  # (`server.unix_socket`). A UNIX socket connection is local by construction,
  # and the socket file's permissions decide who may open it, so a proxy that
  # reaches Amber that way is as trustworthy as one on loopback.
  #
  # The header family comes from `server.trusted_proxy_headers`. A proxy
  # rewrites only the family it manages and passes the other one through
  # from the client unchanged, so Amber reads exactly one family:
  # `X-Forwarded-For` / `X-Forwarded-Proto` by default, or RFC 7239
  # `Forwarded` when *reads_forwarded_header* is `true`.
  #
  # ```
  # networks = ["127.0.0.0/8"].map { |notation| Amber::Support::TrustedProxyNetwork.parse(notation) }
  # trusted_proxies = Amber::Support::TrustedProxies.new(networks, trusts_unix_socket_peers: false)
  # trusted_proxies.trusts?(Socket::IPAddress.new("127.0.0.1", 0)) # => true
  # ```
  struct TrustedProxies
    # The trusted networks. The slice is read-only: writing to it raises.
    getter list_of_networks : Slice(TrustedProxyNetwork)
    getter? trusts_unix_socket_peers : Bool
    getter? reads_forwarded_header : Bool

    def initialize(@list_of_networks : Slice(TrustedProxyNetwork), *,
                   @trusts_unix_socket_peers : Bool,
                   @reads_forwarded_header : Bool = false)
    end

    # Builds the set from *list_of_networks*, copying it into a read-only
    # slice.
    def self.new(list_of_networks : Array(TrustedProxyNetwork), *,
                 trusts_unix_socket_peers : Bool,
                 reads_forwarded_header : Bool = false) : self
      new(
        TrustedProxyNetwork.read_only_slice(list_of_networks),
        trusts_unix_socket_peers: trusts_unix_socket_peers,
        reads_forwarded_header: reads_forwarded_header
      )
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
