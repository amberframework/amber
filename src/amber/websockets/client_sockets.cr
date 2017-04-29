module Amber
  module WebSockets
    module ClientSockets
      extend self
      @@client_sockets = {} of UInt64 => ClientSocket
      @@heartbeat_started = false
      BEAT_INTERVAL = 3.seconds

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

      private def heartbeat
        spawn do
          @@heartbeat_started = true
          @@client_sockets.values.map(&.beat)
          sleep BEAT_INTERVAL
          heartbeat
        end
      end
    end
  end
end