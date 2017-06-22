module Amber
  module WebSockets
    # `ClientSocket` struct maps a user to an [HTTP::WebSocket](https://crystal-lang.org/api/0.22.0/HTTP/WebSocket.html).  For every websocket connection
    # there will be an associated ClientSocket.  Authentication and authorization happen within the `ClientSocket`.  `ClientSocket` will subscribe to `Channel`s,
    # where incoming and outgoing messages are routed through.
    #
    # Example:
    #
    # ```crystal
    # struct UserSocket < Amber::Websockets::ClientSocket
    #   channel "user_channel:*", UserChannel
    #   channel "room_channel:*", RoomChannel
    #
    #   def on_connect
    #     return some_auth_method!
    #   end
    # end
    # ```
    abstract struct ClientSocket
      @@channels = [] of NamedTuple(path: String, channel: Channel)

      property id : UInt64
      property socket : HTTP::WebSocket

      # Add a channel for this socket to listen, publish to
      def self.channel(channel_path, ch)
        @@channels.push({path: channel_path, channel: ch.new(WebSockets.topic_path(channel_path))})
      end

      def self.channels
        @@channels
      end

      def self.get_topic_channel(topic_path)
        topic_channels = @@channels.select { |ch| WebSockets.topic_path(ch[:path]) == topic_path }
        return topic_channels[0][:channel] if topic_channels.any?
      end

      def initialize(@socket)
        @id = @socket.object_id
        @subscription_manager = SubscriptionManager.new
        @socket.on_pong do |msg|
          # TODO: setup heartbeat
        end
      end

      # Authentication and authorization shuould happen here
      def on_connect : Bool
        true
      end

      # Sends ping opcode to client : https://tools.ietf.org/html/rfc6455#section-5.5.2
      def beat
        spawn { @socket.ping }
      end

      def subscribed_to_topic?(topic)
        @subscription_manager.subscriptions.keys.includes?(topic.to_s)
      end

      protected def authorized?
        on_connect
      end

      protected def on_message(message)
        if @socket.closed?
          Amber::Server.instance.log.error "Ignoring message sent to closed socket"
        else
          @subscription_manager.dispatch self, decode(message)
        end
      end

      protected def decode(message)
        # TODO: implement different decoders
        JSON.parse(message)
      end
    end
  end
end
