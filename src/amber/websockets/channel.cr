module Amber
  module WebSockets
    # Sockets subscribe to Channels, where the communication log is handled.  The channel provides functionality
    # to handle socket join `handle_joined` and socket messages `handle_message(msg)`.
    #
    # Example:
    #
    # ```
    # class ChatChannel < Amber::WebSockets::Channel
    #   def handle_joined(client_socket, message)
    #     # functionality when the user joins the channel, optional
    #   end
    #
    #   def handle_leave(client_socket)
    #     # functionality when the user leaves the channel, optional
    #   end
    #
    #   def after_join(client_socket)
    #     # called after handle_joined completes, optional
    #   end
    #
    #   def after_leave(client_socket)
    #     # called after handle_leave completes, optional
    #   end
    #
    #   def on_error(ex, client_socket)
    #     # called when an error occurs during message handling, optional
    #   end
    #
    #   # functionality when a socket sends a message to a channel, required
    #   def handle_message(client_socket, msg)
    #     rebroadcast!(msg)
    #   end
    # end
    # ```
    abstract class Channel
      Log = ::Log.for(self)

      @@adapter : Amber::Adapters::PubSubAdapter?
      @@legacy_adapter : WebSockets::Adapters::MemoryAdapter?

      @topic_path : String

      abstract def handle_message(client_socket, msg)

      # Authorization can happen here
      def handle_joined(client_socket, message); end

      def handle_leave(client_socket); end

      # Called after `handle_joined` completes successfully.
      # Override this to perform post-join logic such as sending welcome messages
      # or notifying other users.
      def after_join(client_socket); end

      # Called after `handle_leave` completes successfully.
      # Override this to perform cleanup logic after a user leaves a channel.
      def after_leave(client_socket); end

      # Called when an error occurs during message handling or channel callbacks.
      # Override this to implement custom error reporting or recovery logic.
      #
      # The default implementation logs the error.
      def on_error(ex : Exception, client_socket)
        Log.error(exception: ex) { "Error in channel #{@topic_path} for socket #{client_socket.id}: #{ex.message}" }
      end

      def initialize(@topic_path); end

      # Called when a socket subscribes to a channel
      def subscribe_to_channel(client_socket, message)
        handle_joined(client_socket, message)
        track_presence(client_socket)
        after_join(client_socket)
      rescue ex : Exception
        on_error(ex, client_socket)
      end

      # Called when a socket unsubscribes from a channel
      def unsubscribe_from_channel(client_socket)
        handle_leave(client_socket)
        untrack_presence(client_socket)
        after_leave(client_socket)
      rescue ex : Exception
        on_error(ex, client_socket)
      end

      # Called from proc when message is returned from the pubsub service
      # This is a class method that handles message dispatch to instances
      def self.on_message(topic_path : String, client_socket_id : String, message : JSON::Any)
        if client_socket = ClientSockets.client_sockets[client_socket_id]?
          # Create a temporary channel instance to handle the message
          channel = new(topic_path)
          channel.handle_message(client_socket, message)
        end
      end

      # Broadcasts a message to all subscribers of the given topic from outside
      # a channel instance. This is useful for sending messages from controllers,
      # background jobs, or other non-channel contexts.
      #
      # Example:
      #
      # ```
      # # From a controller action:
      # ChatChannel.broadcast_to("chat_room:lobby", "msg:new", {"message" => "Server announcement"})
      # ```
      def self.broadcast_to(channel_topic : String, event : String, payload : Hash(String, String))
        message = {
          "event"   => event,
          "topic"   => channel_topic,
          "payload" => payload,
        }
        subscribers = ClientSockets.get_subscribers_for_topic(channel_topic)
        subscribers.each_value do |client_socket|
          begin
            client_socket.socket.send(message.to_json)
          rescue ex : IO::Error
            Log.error(exception: ex) { "Failed to broadcast to socket #{client_socket.id}" }
          end
        end
      end

      # Returns the list of currently present sockets in this channel's topic.
      #
      # Each entry is a Hash with socket_id as key and metadata as value.
      # Metadata includes at minimum "socket_id" and "joined_at".
      def presence_list : Hash(String, Hash(String, String))
        Presence.list(@topic_path)
      end

      # Returns the number of sockets currently present in this channel's topic.
      def presence_count : Int32
        Presence.count(@topic_path)
      end

      # Class-level access to presence data for a given topic.
      def self.presence_list(topic_path : String) : Hash(String, Hash(String, String))
        Presence.list(topic_path)
      end

      # Resets presence tracking. Mainly useful for testing.
      def self.reset_presence
        Presence.reset
      end

      # Helper method for retrieving the adapter not nillable
      protected def adapter
        if pubsub_adapter = @@adapter
          pubsub_adapter
        elsif legacy_adapter = @@legacy_adapter
          legacy_adapter
        else
          setup_pubsub_adapter
        end
      end

      # Sends *message* to all subscribing clients belonging to this channel
      # by using the rebroadcast functionality that sends to all subscribers
      def broadcast!(message, topic = @topic_path)
        rebroadcast!(message)
      end

      def rebroadcast!(message, topic = @topic_path)
        case message
        when Hash
          # Use the existing rebroadcast functionality for hash messages
          internal_rebroadcast!(message)
        else
          # For other message types, convert to the expected format
          formatted_message = {
            "event"   => "message",
            "topic"   => topic,
            "payload" => message,
          }
          internal_rebroadcast!(formatted_message)
        end
      end

      # Ensures the pubsub adapter instance exists, and sets up the message callback
      protected def setup_pubsub_adapter
        # Try to get the new adapter-based pub/sub first
        if adapter_based_pubsub = Amber::Server.instance.adapter_based_pubsub
          @@adapter = adapter_based_pubsub
          # Subscribe with a class-level callback
          @@adapter.not_nil!.subscribe(@topic_path) do |sender_id, message|
            # Call the class method to handle message dispatching
            self.class.on_message(@topic_path, sender_id, message)
          end
          @@adapter.not_nil!
        else
          # Fall back to legacy adapter
          @@legacy_adapter = Amber::Server.pubsub_adapter.as(WebSockets::Adapters::MemoryAdapter)
          @@legacy_adapter.not_nil!.on_message(@topic_path, ->(client_socket_id : String, message : JSON::Any) {
            self.class.on_message(@topic_path, client_socket_id, message)
          })
          @@legacy_adapter.not_nil!
        end
      end

      # Sends *message* to the pubsub service
      protected def dispatch(client_socket, message)
        if adapter = @@adapter
          adapter.publish(@topic_path, client_socket.id, message)
        elsif legacy_adapter = @@legacy_adapter
          legacy_adapter.publish(@topic_path, client_socket, message)
        else
          setup_pubsub_adapter
          dispatch(client_socket, message)
        end
      end

      # Rebroadcast this message to all subscribers of the channel
      # example message: {"event" => "message", "topic" => "rooms:123", "subject" => "msg:new", "payload" => {"message" => "hello"}}
      protected def internal_rebroadcast!(message)
        subscribers = ClientSockets.get_subscribers_for_topic(message["topic"])
        subscribers.each_value(&.socket.send(message.to_json))
      end

      # Tracks a client socket's presence in this channel topic and broadcasts
      # a presence_diff event to all subscribers.
      private def track_presence(client_socket)
        metadata = {
          "socket_id" => client_socket.id,
          "joined_at" => Time.utc.to_rfc3339,
        }

        Presence.track(@topic_path, client_socket.id, metadata)
        broadcast_presence_diff(joins: {client_socket.id => metadata}, leaves: Hash(String, Hash(String, String)).new)
      end

      # Removes a client socket's presence from this channel topic and broadcasts
      # a presence_diff event to all subscribers.
      private def untrack_presence(client_socket)
        removed_metadata = Presence.untrack(@topic_path, client_socket.id)

        unless removed_metadata.empty?
          broadcast_presence_diff(joins: Hash(String, Hash(String, String)).new, leaves: {client_socket.id => removed_metadata})
        end
      end

      # Broadcasts a presence_diff event containing joins and leaves to all channel subscribers.
      private def broadcast_presence_diff(joins : Hash(String, Hash(String, String)), leaves : Hash(String, Hash(String, String)))
        message = {
          "event"   => "presence_diff",
          "topic"   => @topic_path,
          "payload" => {
            "joins"  => joins,
            "leaves" => leaves,
          },
        }

        subscribers = ClientSockets.get_subscribers_for_topic(@topic_path)
        subscribers.each_value do |subscriber|
          begin
            subscriber.socket.send(message.to_json)
          rescue ex : IO::Error
            Log.error(exception: ex) { "Failed to send presence_diff to socket #{subscriber.id}" }
          end
        end
      end
    end
  end
end
