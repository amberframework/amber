module Amber
  module WebSockets
    # Sockets subscribe to Channel's, where the communication log is handled.  The channel provides funcionality
    # to handle socket join `handle_joined` and socket messages `handle_message(msg)`.
    #
    # Example:
    #
    # ```crystal
    # class ChatChannel < Amber::Websockets::Channel
    #   def handle_joined(client_socket)
    #     # functionality when the user joines the channel, optional
    #   end
    #
    #   def handle_leave(client_socket)
    #     # functionality when the user leaves the channel, optional
    #   end
    #
    #   # functionality when a socket sends a message to a channel, required
    #   def handle_message(msg)
    #     rebroadcast!(msg)
    #   end
    # end
    # ```
    abstract class Channel
      @@adapter : WebSockets::Adapters::RedisAdapter? | WebSockets::Adapters::MemoryAdapter?
      @topic_path : String

      abstract def handle_message(msg)

      def handle_joined(client_socket); end

      def handle_leave(client_socket); end

      def initialize(@topic_path); end

      # Called from proc when message is returned from the pubsub service
      def on_message(message)
        handle_message(message)
      end

      # Helper method for retrieving the apdater not nillable
      protected def adapter
        setup_pubsub_adapter if @@adapter.nil?
        @@adapter.not_nil!
      end

      # Called when a socket subscribes to a channel
      protected def subscribe_to_channel(client_socket)
        handle_joined(client_socket)
      end

      # Called when a socket unsubscribes from a channel
      protected def unsubscribe_from_channel(client_socket)
        handle_leave(client_socket)
      end

      # Sends *message* to the pubsub service
      protected def dispatch(message)
        adapter.publish(@topic_path, message)
      end

      # Rebroadcast this message to all subscribers of the channel
      # example message: {"event" => "message", "topic" => "rooms:123", "subject" => "msg:new", "payload" => {"message" => "hello"}}
      protected def rebroadcast!(message)
        subscribers = ClientSockets.get_subscribers_for_topic(message["topic"])
        subscribers.each_value(&.socket.send(message.to_json))
      end

      # Ensure the pubsub adpater instance exists, and set up the on_message proc callback
      protected def setup_pubsub_adapter
        @@adapter = Amber::Server.instance.pubsub_adapter.instance
        @@adapter.not_nil!.on_message(@topic_path, ->(message : JSON::Any) { self.on_message(message); nil })
      end
    end
  end
end
