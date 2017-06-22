module Amber
  module WebSockets
    #
    # Manages the entire collection of ClientSockets.  Manages periodic timers for socket connections (heartbeat).
    #
    module ClientSockets
      extend self
      @@client_sockets = Hash(UInt64, ClientSocket).new
      @@heartbeat_started = false
      BEAT_INTERVAL = 1.minute

      def add_client_socket(client_socket)
        @@client_sockets[client_socket.id] = client_socket
      end

      def remove_client_socket(client_socket)
        @@client_sockets.delete(client_socket.id)
      end

      def client_sockets
        @@client_sockets
      end

      # Implement ping / pong control frames, to prevent stale connections : https://tools.ietf.org/html/rfc6455#section-5.5.2
      def setup_heartbeat
        return if @@heartbeat_started
        heartbeat
      end

      def get_subscribers_for_topic(topic)
        @@client_sockets.select do |k, client_socket|
          client_socket.subscribed_to_topic?(topic.to_s)
        end
      end

      private def heartbeat
        spawn do
          @@heartbeat_started = true
          sleep BEAT_INTERVAL
          @@client_sockets.each_value(&.beat)
          heartbeat
        end
      end
    end
  end
end
