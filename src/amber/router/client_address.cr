require "../support/trusted_proxies"
require "./forwarded_header"

module Amber::Router
  # Decides the IP address of the client behind a request. `HTTP::Request#client_ip`
  # and `Amber::Pipe::ClientIp` call it.
  #
  # When the immediate peer is not a trusted proxy, the client is the peer
  # and every forwarding header is ignored, because whoever opened the
  # connection could have written them.
  #
  # When the peer is a trusted proxy, Amber reads the chain of hops that the
  # proxies appended, from the `for=` parameters of `Forwarded` (RFC 7239)
  # when that header is present, otherwise from `X-Forwarded-For`. It walks
  # the chain from the right, skipping hops that are themselves trusted
  # proxies, and returns the first address that is not. Entries to the left
  # of that address were written by the client or by an untrusted hop and are
  # never read, so a spoofed leftmost entry cannot win.
  #
  # A hop that is not an IP address (`unknown`, an obfuscated identifier, or
  # garbage) ends the walk: nothing to its left can be verified, so the client
  # is the nearest trusted hop that was verified. When every hop is trusted,
  # the farthest one is the client.
  module ClientAddress
    X_FORWARDED_FOR = "X-Forwarded-For"

    # Returns the client address of *request*, or `nil` when no IP address is
    # known (a request built in memory, or a UNIX socket peer with no usable
    # forwarding header). *list_of_header_names* replaces the default
    # `Forwarded` / `X-Forwarded-For` lookup with the first of those headers
    # that is present.
    def self.resolve(request : ::HTTP::Request,
                     trusted_proxies : Amber::Support::TrustedProxies,
                     list_of_header_names : Array(String)? = nil) : Socket::IPAddress?
      peer = request.remote_address
      peer_address = peer.as?(Socket::IPAddress)
      return peer_address unless trusted_proxies.trusts?(peer)

      list_of_hops = list_of_forwarded_hops(request.headers, list_of_header_names)
      nearest_verified_address = peer_address

      list_of_hops.reverse_each do |hop|
        hop_address = ForwardedHeader.node_address(hop)
        return nearest_verified_address unless hop_address
        return hop_address unless trusted_proxies.trusts?(hop_address)

        nearest_verified_address = hop_address
      end

      nearest_verified_address
    end

    private def self.list_of_forwarded_hops(headers : ::HTTP::Headers, list_of_header_names : Array(String)?) : Array(String)
      if list_of_header_names
        list_of_header_names.each do |header_name|
          list_of_values = ForwardedHeader.list_of_values(headers, header_name)
          return list_of_values unless list_of_values.empty?
        end
        return [] of String
      end

      if headers.has_key?(ForwardedHeader::FORWARDED)
        # An element without `for=` is a hop whose address is unknown.
        ForwardedHeader.list_of_parameter_values(headers, "for").map { |value| value || "" }
      else
        ForwardedHeader.list_of_values(headers, X_FORWARDED_FOR)
      end
    end
  end
end
