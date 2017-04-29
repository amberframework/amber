module Amber
  module WebSockets
    struct Subscriptions
      property subscriptions = Hash(String, String).new

      def initialize(@connection : HTTP::WebSocket);end

      def execute_command(message)
        event = message["event"]?
        return unless event

        case event
        when "subscribe" then subscribe message
        when "message" then message message
        when "unsubscribe" then unsubscribe message
        else
          Amber::Server.instance.log.error "Uncaptured event #{event}"
        end
      end

      def subscribe(message)
        puts "add #{message}"
      end

      def message(message)
        puts "message #{message}"
      end

      def unsubscribe(message)
        puts "unsubscribe #{message}"
      end
    end
  end
end