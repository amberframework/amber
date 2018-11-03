require "base64"
require "yaml"
require "openssl/hmac"

module Amber
  module Router
    module Flash
      def self.from_session(flash_content)
        FlashStore.from_session(flash_content)
      end

      class FlashStore
        @store : Hash(String, String)
        forward_missing_to @store

        def self.from_session(json)
          flash = new
          values = JSON.parse(json)
          values.as_h.each { |k, v| flash[k.to_s] = v.to_s }
          flash
        rescue e : JSON::ParseException
          new
        end

        def initialize
          @store = {} of String => String
          @read = [] of String
          @now = [] of String
        end

        def fetch(key : String)
          @read << key
          @store.fetch(key, nil)
        end

        def fetch(key : Symbol)
          fetch key.to_s
        end

        def fetch(key : String, default_value : String?)
          @read << key
          @store.fetch(key, default_value)
        end

        def fetch(key : Symbol, default_value : String?)
          fetch key.to_s, default_value
        end

        def []=(key : Symbol, value : String)
          @store[key.to_s] = value
        end

        def []?(key : Symbol)
          fetch(key.to_s, nil)
        end

        def []?(key : String)
          fetch(key, nil)
        end

        def [](key : Symbol)
          fetch(key)
        end

        def each
          @store.each do |key, value|
            yield({key, value})
            @read << key
          end
        end

        def now(key, value)
          @now << key
          self[key] = value
        end

        def keep(key = nil)
          @read.delete key
          @now.delete key
        end

        def alert
          self["alert"]
        end

        def alert=(message)
          self["alert"] = message
        end

        def notice
          self["notice"]
        end

        def notice=(message)
          self["notice"] = message
        end

        def to_session
          reject { |key, _| @read.includes? key }.reject { |key, _| @now.includes? key }.to_json
        end
      end
    end
  end
end
