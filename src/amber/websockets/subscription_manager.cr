module Amber
  module WebSockets
    # `SubscriptionManager` manages the list of channel subscriptions for the socket connection.
    # Also handles dispatching actions (messages) to the appropriate channel.
    struct SubscriptionManager
      Log = ::Log.for(self)
      property subscriptions = Hash(String, Channel).new

      def dispatch(client_socket, message)
        event = message["event"]?
        return unless event

        case event
        when "join"    then join client_socket, message
        when "message" then message client_socket, message
        when "leave"   then leave client_socket, message
        else
          Log.error { "Uncaptured event #{event}" }
        end
      end

      private def join(client_socket, message)
        return if subscriptions[message["topic"]]?
        if channel = client_socket.class.get_topic_channel(WebSockets.topic_path(message["topic"]))
          channel.subscribe_to_channel(client_socket, message)
          subscriptions[message["topic"].as_s] = channel
        end
      end

      private def message(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          channel.dispatch(client_socket, message)
        end
      end

      private def leave(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          channel.unsubscribe_from_channel(client_socket)
          subscriptions.delete(message["topic"].as_s)
        end
      end
    end
  end
end
