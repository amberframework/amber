module Amber
  module WebSockets
    # Module-level presence tracking for WebSocket channels.
    #
    # This module stores presence data outside the Channel class hierarchy
    # to avoid Crystal's class variable inheritance behavior where each subclass
    # gets its own copy of `@@` variables. By using a module with `extend self`,
    # all channel classes share the same presence store.
    #
    # Presence data tracks which client sockets are present in each channel topic,
    # along with metadata such as when they joined. This enables features like
    # user lists, online indicators, and presence_diff events.
    module Presence
      extend self

      @@store = Hash(String, Hash(String, Hash(String, String))).new
      @@mutex = Mutex.new

      # Tracks a client socket's presence in the given topic.
      def track(topic_path : String, socket_id : String, metadata : Hash(String, String))
        @@mutex.synchronize do
          @@store[topic_path] ||= Hash(String, Hash(String, String)).new
          @@store[topic_path][socket_id] = metadata
        end
      end

      # Removes a client socket's presence from the given topic.
      # Returns the metadata that was removed, or an empty hash if not found.
      def untrack(topic_path : String, socket_id : String) : Hash(String, String)
        @@mutex.synchronize do
          if topic_presence = @@store[topic_path]?
            topic_presence.delete(socket_id) || Hash(String, String).new
          else
            Hash(String, String).new
          end
        end
      end

      # Returns all presence entries for the given topic.
      def list(topic_path : String) : Hash(String, Hash(String, String))
        @@mutex.synchronize do
          @@store[topic_path]? || Hash(String, Hash(String, String)).new
        end
      end

      # Returns the number of sockets present in the given topic.
      def count(topic_path : String) : Int32
        list(topic_path).size
      end

      # Returns whether a socket is present in the given topic.
      def has_socket?(topic_path : String, socket_id : String) : Bool
        @@mutex.synchronize do
          if topic_presence = @@store[topic_path]?
            topic_presence.has_key?(socket_id)
          else
            false
          end
        end
      end

      # Clears all presence data. Useful for testing.
      def reset
        @@mutex.synchronize do
          @@store.clear
        end
      end
    end
  end
end
