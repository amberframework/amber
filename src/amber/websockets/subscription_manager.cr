module Amber
  module WebSockets
    # `SubscriptionManager` manages the list of channel subscriptions for the socket connection.
    # Also handles dispatching actions (messages) to the appropriate channel.
    struct SubscriptionManager
      property subscriptions = Hash(String, Channel).new

      def dispatch(client_socket, message)
        event = message["event"]?
        return unless event

        case event
        when "join"    then join client_socket, message
        when "message" then message client_socket, message
        when "leave"   then unsubscribe client_socket, message
        else
          Amber::Server.instance.log.error "Uncaptured event #{event}"
        end
      end

      def join(client_socket, message)
        return if subscriptions[message["topic"]]?
        topic = message["topic"].as_s.split(":")[0]
        if channel = client_socket.class.get_topic_channel(topic)
          channel.subscribe_to_channel
          subscriptions[message["topic"].as_s] = channel
        end
      end

      def message(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          channel.dispatch(message)
        end
      end

      def unsubscribe(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          subscriptions.delete(message["topic"].as_s)
        end
      end
    end
  end
end
