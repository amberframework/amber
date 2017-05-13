module Amber::Router
  module Flash
    # clear the flash messages.
    def clear_flash
      @flash = FlashHash.new
    end

    # Holds a hash of flash variables.  This can be used to hold data between
    # requests. Once a flash message is read, it is marked for removal.
    def flash
      @flash ||= FlashHash.new
    end

    # A hash that keeps track if its been accessed
    class FlashHash < Hash(String, String)
      def initialize
        @read = [] of String
        super
      end

      def fetch(key)
        @read << key
        super
      end

      def each
        current = @first
        while current
          yield({current.key, current.value})
          @read << current.key
          current = current.fore
        end
        self
      end

      def unread
        reject { |key, _| !@read.includes? key }
      end
    end
  end
end