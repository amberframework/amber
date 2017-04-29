module Amber
  module WebSockets
    struct Subscriptions
      property subscriptions = Hash(String, String).new

      def initialize(@connection : HTTP::WebSocket);end
    end
  end
end