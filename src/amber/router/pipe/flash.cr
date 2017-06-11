require "base64"
require "yaml"
require "openssl/hmac"

module Amber
  module Pipe
    # The flash handler provides a mechanism to pass flash message between
    # requests.
    class Flash < Base
      property :key

      def initialize
        @key = "#{Server.settings.project_name}.flash"
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
        yaml = Base64.decode_string(data)
        values = YAML.parse(yaml)
        values.each do |key, value|
          flash[key.to_s] = value.to_s
        end
      end

      private def encode(flash)
        data = Base64.encode(flash.to_yaml)
        return data
      end
    end
  end

  module Router
    module Flash
      # clear the flash messages.
      def clear_flash
        @flash = Params.new
      end

      # Holds a hash of flash variables.  This can be used to hold data between
      # requests. Once a flash message is read, it is marked for removal.
      def flash
        @flash ||= Params.new
      end

      # A hash that keeps track if its been accessed
      class Params < Hash(String, String)
        def initialize
          @read = [] of String
          super
        end

        def read
          @read
        end

        def []=(key : String | Symbol, value : V)
          super(key.to_s, value)
        end

        def [](key)
          fetch(key, nil)
        end

        # TODO: Refactor this soon.
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
          # TODO: unread marks them as read. Maybe fix this. It shouldn't actually matter since it get's reloaded next request.
          reject { |key, _| @read.includes? key }
        end

        def find_entry(key)
          key = key.to_s
          @read << key
          super(key)
        end
      end
    end
  end
end
