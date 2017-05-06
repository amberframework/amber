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
        when "join"        then join client_socket, message
        when "message"     then message client_socket, message
        when "unsubscribe" then unsubscribe client_socket, message
        else
          Amber::Server.instance.log.error "Uncaptured event #{event}"
        end
      end

      def join(client_socket, message)
        return if subscriptions[message["channel"]]?
        topic = message["channel"].as_s.split(":")[0]
        if channel = client_socket.class.get_channel_from_topic(topic)
          channel.subscribe_to_channel
          subscriptions[message["channel"].as_s] = channel
        end
      end

      def message(client_socket, message)
        if channel = subscriptions[message["channel"].as_s]?
          channel.dispatch(message)
        end
      end

      def unsubscribe(client_socket, message)
        puts "unsubscribe #{message}"
      end
    end
  end
end
