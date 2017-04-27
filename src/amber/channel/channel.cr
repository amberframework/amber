module Amber
  module WebSockets
    class Channel
      property name : String

      def initialize(@name);end

      def self.subscribe(channel_name)
        ch = self.new(name)
        Amber::WebSockets::Channels.add_channel(ch)
        ch.join
      end
    end
  end
end