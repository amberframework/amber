require "base64"
require "yaml"
require "openssl/hmac"

module Amber
  module Pipe
    class Flash < Base
      PARAM_KEY = "_flash"

      def call(context)
        call_next(context)
      ensure
        session = context.session
        flash = context.flash.not_nil!
        session[PARAM_KEY] = flash.to_session
      end
    end
  end

  module Router
    module Flash
      def self.from_session_value(flash_content)
        FlashStore.from_session_value(flash_content)
      end

      class FlashNow
        property :flash

        def initialize(flash)
          @flash = flash
        end

        def []=(key, value)
          @flash[key] = value
          @flash.discard(key)
          value
        end

        def [](k)
          @flash[k.to_s]
        end

        # Convenience accessor for <tt>flash.now["alert"]=</tt>.
        def alert=(message)
          self["alert"] = message
        end

        # Convenience accessor for <tt>flash.now["notice"]=</tt>.
        def notice=(message)
          self["notice"] = message
        end
      end

      class FlashStore
        include Enumerable(String)

        JSON.mapping({
          flashes: Hash(String | Symbol, String),
          discard: Set(String),
        })

        def self.from_session_value(json)
          from_json(json).tap(&.sweep)
        rescue e : JSON::ParseException
          new
        end

        delegate :each, to: :flashes

        def initialize
          @flashes = Hash(String | Symbol, String).new
          @discard = Set(String).new
        end

        def discard=(value : Array(String))
          @discard = value.to_set
        end

        def []=(key, value)
          k = key.to_s
          @discard.delete k
          @flashes[k] = value
        end

        def [](key)
          @flashes[key.to_s]?
        end

        def update(hash : Hash(String, String)) # :nodoc:
          @discard.subtract hash.keys
          @flashes.update hash
          self
        end

        def keys
          @flashes.keys
        end

        def has_key?(key)
          @flashes.has_key?(key.to_s)
        end

        def delete(key)
          @discard.delete key.to_s
          @flashes.delete key.to_s
          self
        end

        def merge!(other : Hash(String, String))
          other.each do |k, v|
            @flashes[k.to_s] = v
          end
          self
        end

        def to_hash
          @flashes.dup
        end

        def empty?
          @flashes.empty?
        end

        def clear
          @discard.clear
          @flashes.clear
        end

        def now
          @now ||= FlashNow.new(self)
        end

        def keep(key = nil)
          k = key.to_s if key
          @discard.subtract k
          k ? self[k] : self
        end

        def discard(key = nil)
          k = key ? [key.to_s] : self.keys.map(&.to_s)
          @discard.concat k.to_set
          k ? self[k] : self
        end

        def sweep
          @discard.each { |k| @flashes.delete k }
          @discard = @discard.map(&.to_s).to_set | @flashes.keys.map(&.to_s).to_set
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
          {"flashes": @flashes, "discard": @discard}.to_json
        end
      end
    end
  end
end
