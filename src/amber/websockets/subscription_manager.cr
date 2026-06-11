module Amber
  module WebSockets
    # `SubscriptionManager` manages the list of channel subscriptions for the socket connection.
    # Also handles dispatching actions (messages) to the appropriate channel.
    #
    # Errors in one channel are isolated and do not affect other channels or crash
    # the socket connection. Errors are forwarded to the channel's `on_error` callback
    # and to the socket's `handle_error` method for reporting.
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
      rescue ex : Exception
        Log.error(exception: ex) { "Error dispatching event '#{message["event"]?}' for socket #{client_socket.id}: #{ex.message}" }
        client_socket.handle_error(ex, "subscription_dispatch")
      end

      private def join(client_socket, message)
        return if subscriptions[message["topic"]]?
        if channel = client_socket.class.get_topic_channel(WebSockets.topic_path(message["topic"]))
          channel.subscribe_to_channel(client_socket, message)
          subscriptions[message["topic"].as_s] = channel
        end
      rescue ex : Exception
        Log.error(exception: ex) { "Error joining channel #{message["topic"]?}: #{ex.message}" }
        client_socket.handle_error(ex, "channel_join")
      end

      private def message(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          channel.dispatch(client_socket, message)
        end
      rescue ex : Exception
        topic = message["topic"]?.try(&.as_s) || "unknown"
        if channel = subscriptions[topic]?
          channel.on_error(ex, client_socket)
        end
        Log.error(exception: ex) { "Error handling message in channel #{topic}: #{ex.message}" }
        client_socket.handle_error(ex, "channel_message")
      end

      private def leave(client_socket, message)
        if channel = subscriptions[message["topic"].as_s]?
          channel.unsubscribe_from_channel(client_socket)
          subscriptions.delete(message["topic"].as_s)
        end
      rescue ex : Exception
        Log.error(exception: ex) { "Error leaving channel #{message["topic"]?}: #{ex.message}" }
        client_socket.handle_error(ex, "channel_leave")
      end
    end
  end
end
