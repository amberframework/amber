module Amber
  module WebSockets
    class Channel
      property name : String

      def initialize(@name);end

      def self.subscribe(channel_name)
      end
    end
  end
end