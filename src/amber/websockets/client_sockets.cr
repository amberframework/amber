module Amber
  module WebSockets
    #
    # Manages the entire collection of ClientSockets.  Manages periodic timers for socket connections (heartbeat).
    # Also manages disconnected connection state for reconnection recovery.
    #
    module ClientSockets
      extend self
      Log = ::Log.for(self)

      @@client_sockets = Hash(String, ClientSocket).new

      # Tracks recently disconnected connections for reconnection recovery.
      # Keys are connection_id values, values hold the disconnect time, buffered messages,
      # and the list of topic subscriptions the socket had.
      @@disconnected_connections = Hash(String, DisconnectedConnection).new
      @@disconnected_mutex = Mutex.new

      # Maximum number of messages to buffer per disconnected connection.
      @@max_message_buffer_size : Int32 = ClientSocket::DEFAULT_MESSAGE_BUFFER_SIZE

      # How long a disconnected connection can be reconnected.
      @@reconnect_window : Time::Span = ClientSocket::RECONNECT_WINDOW

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
        @@client_sockets.delete(client_socket.id)
      end

      def client_sockets
        @@client_sockets
      end

      def get_subscribers_for_topic(topic)
        @@client_sockets.select do |_, client_socket|
          # Check if the client socket is subscribed to this specific topic
          client_socket.subscribed_to_topic?(topic.to_s)
        end
      end

      # Stores the state of a disconnected connection so it can be recovered
      # when the client reconnects within the reconnection window.
      def track_disconnection(client_socket)
        @@disconnected_mutex.synchronize do
          @@disconnected_connections[client_socket.connection_id] = DisconnectedConnection.new(
            connection_id: client_socket.connection_id,
            disconnected_at: Time.utc,
            list_of_subscribed_topics: Array(String).new,
            list_of_buffered_messages: Array(String).new
          )
        end

        # Schedule cleanup after the reconnection window expires
        spawn do
          sleep @@reconnect_window
          @@disconnected_mutex.synchronize do
            if entry = @@disconnected_connections[client_socket.connection_id]?
              if Time.utc - entry.disconnected_at >= @@reconnect_window
                @@disconnected_connections.delete(client_socket.connection_id)
              end
            end
          end
        end
      end

      # Buffers a message for a disconnected connection. If the buffer is full,
      # the oldest message is dropped.
      def buffer_message(connection_id : String, message : String)
        @@disconnected_mutex.synchronize do
          if entry = @@disconnected_connections[connection_id]?
            entry.list_of_buffered_messages << message
            if entry.list_of_buffered_messages.size > @@max_message_buffer_size
              entry.list_of_buffered_messages.shift
            end
          end
        end
      end

      # Attempts to recover a disconnected connection. Returns the buffered
      # messages if the connection_id is found and still within the reconnection
      # window, otherwise returns nil.
      def recover_connection(connection_id : String) : DisconnectedConnection?
        @@disconnected_mutex.synchronize do
          if entry = @@disconnected_connections.delete(connection_id)
            if Time.utc - entry.disconnected_at < @@reconnect_window
              return entry
            end
          end
          nil
        end
      end

      # Returns whether a disconnected connection exists for the given connection_id.
      def has_disconnected_connection?(connection_id : String) : Bool
        @@disconnected_mutex.synchronize do
          @@disconnected_connections.has_key?(connection_id)
        end
      end

      # Configures the reconnection window duration.
      def reconnect_window=(duration : Time::Span)
        @@reconnect_window = duration
      end

      # Configures the maximum message buffer size for disconnected connections.
      def max_message_buffer_size=(size : Int32)
        @@max_message_buffer_size = size
      end

      # Clears all disconnected connection state. Useful for testing.
      def clear_disconnected_connections
        @@disconnected_mutex.synchronize do
          @@disconnected_connections.clear
        end
      end
    end

    # Holds the state of a disconnected connection for recovery.
    record DisconnectedConnection,
      connection_id : String,
      disconnected_at : Time,
      list_of_subscribed_topics : Array(String),
      list_of_buffered_messages : Array(String)
  end
end
