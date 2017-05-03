module Amber
  module WebSockets
    abstract class Channel
      def initialize();end

      abstract def joined

      def subscribe_to_channel
        joined
      end
    end
  end
end