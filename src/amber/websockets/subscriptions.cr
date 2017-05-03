module Amber
  module WebSockets
    struct Subscriptions
      property subscriptions = Hash(String, Channel).new

      def dispatch(client_socket, message)
        event = message["event"]?
        return unless event

        case event
        when "join" then join client_socket, message
        when "message" then message client_socket, message
        when "unsubscribe" then unsubscribe client_socket, message
        else
          Amber::Server.instance.log.error "Uncaptured event #{event}"
        end
      end

      def join(client_socket, message)
        return if subscriptions[message["channel"]]?
        topic = message["channel"].as_s.split(":")[0]
        channel = client_socket.class.channels.select{|ch| ch[:path].split(":")[0] == topic }[0][:channel]
        channel.subscribe_to_channel
        subscriptions[message["channel"].as_s] = channel
      end

      def message(client_socket, message)
        puts "message #{message}"
      end

      def unsubscribe(client_socket, message)
        puts "unsubscribe #{message}"
      end
    end
  end
end