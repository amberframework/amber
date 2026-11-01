module Amber
  module Pipe
    # Saves the real client IP address to `context.client_ip`.
    #
    # By default it uses `HTTP::Request#client_ip`: the peer's own address
    # for an untrusted peer, and for a trusted proxy (`server.trusted_proxies`)
    # the nearest untrusted hop in the header family the proxy writes
    # (`X-Forwarded-For`, or `Forwarded: for=`), read from the right. See
    # `Amber::Router::ClientAddress`.
    #
    # Given header names, it reads the first of those headers that is present
    # instead, with the same rule: the header is believed only from a trusted
    # proxy, and walked from the right. Name a header only when the trusted
    # proxy sets it on every request and so overwrites any value a client
    # sent; a proxy passes other headers through unchanged, and the client
    # would choose its own address.
    class ClientIp < Base
      @list_of_header_names : Array(String)?

      def initialize
        @list_of_header_names = nil
      end

      def initialize(header : String)
        @list_of_header_names = [header]
      end

      def initialize(list_of_header_names : Array(String))
        @list_of_header_names = list_of_header_names
      end

      def call(context : HTTP::Server::Context)
        request = context.request
        context.client_ip = Amber::Router::ClientAddress.resolve(request, request.trusted_proxies, @list_of_header_names)
        call_next(context)
      end
    end
  end
end
