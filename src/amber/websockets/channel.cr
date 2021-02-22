module Amber
  module WebSockets
    # Sockets subscribe to Channels, where the communication log is handled.  The channel provides functionality
    # to handle socket join `handle_joined` and socket messages `handle_message(msg)`.
    #
    # Example:
    #
    # ```
    # class ChatChannel < Amber::Websockets::Channel
    #   def handle_joined(client_socket)
    #     # functionality when the user joins the channel, optional
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

      abstract def handle_message(client_socket, msg)

      # Authorization can happen here
      def handle_joined(client_socket, message); end

      def handle_leave(client_socket); end

      def initialize(@topic_path); end

      # Called from proc when message is returned from the pubsub service
      def on_message(client_socket_id, message)
        client_socket = ClientSockets.client_sockets[client_socket_id]?
        handle_message(client_socket, message)
      end

      # Helper method for retrieving the adapter not nillable
      protected def adapter
        if pubsub_adapter = @@adapter
          pubsub_adapter
        else
          setup_pubsub_adapter
        end
      end

      # Called when a socket subscribes to a channel
      protected def subscribe_to_channel(client_socket, message)
        handle_joined(client_socket, message)
      end

      # Called when a socket unsubscribes from a channel
      protected def unsubscribe_from_channel(client_socket)
        handle_leave(client_socket)
      end

      # Sends *message* to the pubsub service
      protected def dispatch(client_socket, message)
        adapter.publish(@topic_path, client_socket, message)
      end

      # Rebroadcast this message to all subscribers of the channel
      # example message: {"event" => "message", "topic" => "rooms:123", "subject" => "msg:new", "payload" => {"message" => "hello"}}
      protected def rebroadcast!(message)
        subscribers = ClientSockets.get_subscribers_for_topic(message["topic"])
        subscribers.each_value(&.socket.send(message.to_json))
      end

      # Ensure the pubsub adapter instance exists, and set up the on_message proc callback
      protected def setup_pubsub_adapter
        @@adapter = Amber::Server.pubsub_adapter
        if pubsub_adapter = @@adapter
          pubsub_adapter.on_message(@topic_path, Proc(String, JSON::Any, Nil).new { |client_socket_id, message|
            self.on_message(client_socket_id, message)
          })
          pubsub_adapter
        else
          raise "Invalid @@adapter on Amber::WebSockets::Channel"
        end
      end
    end
  end
end
