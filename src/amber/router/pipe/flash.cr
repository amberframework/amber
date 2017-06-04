require "base64"
require "json"
require "openssl/hmac"

module Amber
  module Pipe
    # The flash handler provides a mechanism to pass flash message between
    # requests.
    class Flash < Base
      property :key

      def self.instance
        @@instance ||= new
      end

      def initialize
        @key = "amber.flash"
      end

      def call(context : HTTP::Server::Context)
        cookies = context.request.cookies
        decode(context.flash, cookies[@key].value) if cookies.has_key?(@key)
        call_next(context)
        value = encode(context.flash.unread)
        cookies = context.response.cookies
        cookies << HTTP::Cookie.new(@key, value)
        cookies.add_response_headers(context.response.headers)
        context
      end

      private def decode(flash, data)
        json = Base64.decode_string(data)
        values = JSON.parse(json)
        values.each do |key, value|
          flash[key.to_s] = value.to_s
        end
      end

      private def encode(flash)
        data = Base64.encode(flash.to_json)
        return data
      end
    end
  end

  module Router
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
end
