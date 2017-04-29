module Amber
  module WebSockets
    abstract class Channel
      property name : String

      def initialize(@name);end

      abstract def joined
    end
  end
end