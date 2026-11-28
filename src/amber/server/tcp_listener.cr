require "socket"

module Amber
  class Server
    # The `TCPServer` Amber's plain-HTTP listener accepts connections on. When
    # `tcp_nodelay?` (`server.tcp_nodelay`, on by default), each accepted
    # socket gets `TCP_NODELAY`, so a small write (a WebSocket message, a short
    # response) goes out at once instead of waiting for the ACK of the write
    # before it, which a peer delaying its ACKs holds back for up to 40 ms on
    # Linux.
    #
    # ```
    # listener = Amber::Server::TCPListener.new("0.0.0.0", 3000, reuse_port: true)
    # listener.tcp_nodelay = Amber.settings.server.tcp_nodelay?
    # http_server.bind(listener)
    # ```
    class TCPListener < TCPServer
      property? tcp_nodelay : Bool = true

      def accept? : TCPSocket?
        socket = super
        set_tcp_nodelay(socket) if socket && tcp_nodelay?
        socket
      end

      # A connection the peer has already reset can refuse the option; its
      # own first read or write reports that, so the accept goes on.
      private def set_tcp_nodelay(socket : TCPSocket) : Nil
        socket.tcp_nodelay = true
      rescue ::Socket::Error
      end
    end
  end
end
