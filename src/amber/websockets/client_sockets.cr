module Amber
  module WebSockets
    #
    # Manages the entire collection of ClientSockets.  Manages periodic timers for socket connections (heartbeat).
    #
    module ClientSockets
      extend self
      @@client_sockets = Hash(String, ClientSocket).new

      def add_client_socket(client_socket)
        @@client_sockets[client_socket.id] = client_socket

        # send ping & receive pong control frames, to prevent stale connections : https://tools.ietf.org/html/rfc6455#section-5.5.2
        spawn do
          while client_socket && !client_socket.socket.closed?
            
            sleep ClientSocket::BEAT_INTERVAL
            client_socket.beat
          end
        end

      end

      def remove_client_socket(client_socket)
        if @@client_sockets.has_key?(client_socket.id)
          @@client_sockets.delete(client_socket.id)
        end
      end

      def client_sockets
        @@client_sockets
      end

      def get_subscribers_for_topic(topic)
        @@client_sockets.select do |_, client_socket|
          client_socket.subscribed_to_topic?(topic.to_s)
        end
      end
    end
  end
end
