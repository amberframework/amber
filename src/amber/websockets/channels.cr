module Amber
  module WebSockets
    module Channels
      extend self
      @@channels = [] of Channel

      def add_channel(channel)
        @@channels << channel unless @@channels.select{|ch| ch.name === channel.name }.any?
      end
    end
  end
end