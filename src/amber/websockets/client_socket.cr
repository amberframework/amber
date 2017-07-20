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

      MAX_SOCKET_IDLE_TIME = 16.minutes
      BEAT_INTERVAL        = 5.minutes

      property id : UInt64
      property socket : HTTP::WebSocket
      private property pongs = Array(Time).new
      private property pings = Array(Time).new

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
          @pongs.push(Time.now)
          @pongs.delete_at(0) if @pongs.size > 3
        end
      end

      # Authentication and authorization shuould happen here
      def on_connect : Bool
        true
      end

      # Sends ping opcode to client : https://tools.ietf.org/html/rfc6455#section-5.5.2
      protected def beat
        @socket.ping
        @pings.push(Time.now)
        @pings.delete_at(0) if @pings.size > 3
        check_alive!
      rescue ex : IO::Error
        disconnect!
      end

      protected def subscribed_to_topic?(topic)
        @subscription_manager.subscriptions.keys.includes?(topic.to_s)
      end

      protected def disconnect!
        ClientSockets.remove_client_socket(self)
        @socket.close unless @socket.closed?
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

      private def check_alive!
        return unless @pings.size == 3

        # disconnect if no pongs have been received
        #  or no pongs have been received beyond the threshold time
        if @pongs.empty? || (@pings.last - @pongs.first) > MAX_SOCKET_IDLE_TIME
          disconnect!
        end
      end
    end
  end
end
