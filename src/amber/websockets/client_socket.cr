module Amber
  module WebSockets
    # `ClientSocket` struct maps a user to an [HTTP::WebSocket](https://crystal-lang.org/api/0.22.0/HTTP/WebSocket.html).  For every websocket connection
    # there will be an associated ClientSocket.  Authentication and authorization happen within the `ClientSocket`.  `ClientSocket` will subscribe to `Channel`s,
    # where incoming and outgoing messages are routed through.
    #
    # Example:
    #
    # ```
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
      Log = ::Log.for(self)

      @@channels = [] of NamedTuple(path: String, channel: Channel)

      MAX_SOCKET_IDLE_TIME = 100.seconds
      BEAT_INTERVAL        = 30.seconds

      protected getter id : String
      getter socket : HTTP::WebSocket
      protected getter context : HTTP::Server::Context
      protected getter raw_params : Amber::Router::Params
      protected getter params : Amber::Validators::Params
      protected getter session : Amber::Router::Session::AbstractStore?
      protected getter cookies : Amber::Router::Cookies::Store?
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

      # Broadcast a message to all subscribers of the topic
      #
      # ```
      # UserSocket.broadcast("message", "chats_room:1", "msg:new", {"message" => "test"})
      # ```
      def self.broadcast(event : String, topic : String, subject : String, payload : Hash)
        if channel = get_topic_channel(WebSockets.topic_path(topic))
          channel.rebroadcast!({
            "event"   => event,
            "topic"   => topic,
            "subject" => subject,
            "payload" => payload,
          })
        end
      end

      def initialize(@socket, @context)
        @id = UUID.random.to_s
        @subscription_manager = SubscriptionManager.new
        @raw_params = @context.params
        @params = Amber::Validators::Params.new(@raw_params)
        @socket.on_pong do
          @pongs.push(Time.utc)
          @pongs.delete_at(0) if @pongs.size > 3
        end
      end

      # Authentication and authorization can happen here
      def on_connect : Bool
        true
      end

      # On socket disconnect functionality
      def on_disconnect; end

      protected def session
        @session ||= @context.session
      end

      protected def cookies
        @cookies ||= @context.cookies
      end

      # Sends ping opcode to client : https://tools.ietf.org/html/rfc6455#section-5.5.2
      protected def beat
        @socket.send("ping")
        @socket.ping
        @pings.push(Time.utc)
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
          Log.error { "Ignoring message sent to closed socket" }
        else
          @subscription_manager.dispatch self, decode_message(message)
        end
      end

      protected def decode_message(message)
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
