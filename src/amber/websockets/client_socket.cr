module Amber
  module WebSockets
    # `ClientSocket` struct maps a user to an [HTTP::WebSocket](https://crystal-lang.org/api/0.22.0/HTTP/WebSocket.html).  For every websocket connection
    # there will be an associated ClientSocket.  Authentication and authorization happen within the `ClientSocket`.  `ClientSocket` will subscribe to `Channel`s,
    # where incoming and outgoing messages are routed through.
    #
    # Example:
    #
    # ```crystal
    #   struct UserSocket < Amber::Websockets::ClientSocket
    #     channel "user_channel/*", UserChannel
    #     channel "room_channel/*", RoomChannel
    #
    #     def on_connect
    #       return some_auth_method!
    #     end
    #   end
    # ```
    abstract struct ClientSocket
      @@channels = [] of NamedTuple(path: String, channel: Channel.class)

      property id : UInt64
      property socket : HTTP::WebSocket

      # Add a channel for this socket to listen, publish to
      def self.channel(channel_path, ch)
        @@channels.push({path: channel_path, channel: ch})
      end

      def self.channels
        @@channels
      end

      def initialize(@socket)
        @id = @socket.object_id
        @subscriptions = Subscriptions.new(self.socket)
        self.on_connect
      end

      # Authentication and authorization shuould happen here
      def on_connect : Bool
        true
      end

      # Sends ping opcode to client : https://tools.ietf.org/html/rfc6455#section-5.5.2
      def beat
        puts "do beat"
      end

      protected def authorized?
        on_connect
      end
      
    end
  end
end