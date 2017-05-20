module Amber
  module WebSockets
    # Sockets subscribe to Channel's, where the communication log is handled.  The channel provides funcionality
    # to handle socket join `handle_joined` and socket messages `handle_message(msg)`.
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

      # Rebroadcast this message to all subscribers of the channel
      protected def rebroadcast!(msg)
        subscribers = ClientSockets.get_subscribers_for_topic(msg["topic"])
        subscribers.each_value(&.socket.send(msg.to_json))
      end
    end
  end
end
