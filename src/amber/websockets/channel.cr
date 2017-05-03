module Amber
  module WebSockets
    abstract class Channel
      def initialize; end

      abstract def handle_joined
      abstract def handle_message(msg)

      protected def subscribe_to_channel
        handle_joined
      end

      protected def dispatch(msg)
        handle_message(msg)
      end

      protected def rebroadcast!(msg)
        subscribers = ClientSockets.get_subscribers(msg["channel"])
        subscribers.map(&.socket.send(msg.to_s))
      end
    end
  end
end
