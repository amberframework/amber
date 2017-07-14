require "base64"
require "yaml"
require "openssl/hmac"

module Amber
  module Pipe
    class Flash < Base
      def call(context)
        call_next(context)
      ensure
        session = context.session
        flash = context.flash.not_nil!
        session["_flash"] = flash.to_session
        context.cookies.write(context.response.headers)
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
          flashes: Hash(String, String),
          discard: Set(String),
        })

        def self.from_session_value(json)
          from_json(json).tap(&.sweep)
        rescue e : JSON::ParseException
          new
        end

        def each(&block : T -> _)
          @flashes.each do |k, v|
            block.call(k, v)
          end
        end

        def initialize
          @flashes = Hash(String, String).new
          @discard = Set(String).new
        end

        def discard=(value : Array(String))
          @discard = value.to_set
        end

        def []=(key, value)
          discard.delete key
          @flashes[key] = value
        end

        def [](key)
          @flashes[key]?
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
          @flashes.has_key?(key)
        end

        def delete(key)
          @discard.delete key
          @flashes.delete key
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
          key = key.to_s if key
          @discard.subtract key
          key ? self[key] : self
        end

        def discard(key = nil)
          keys = key ? [key] : self.keys
          @discard.concat keys.to_set
          key ? self[key] : self
        end

        def sweep
          @discard.each { |k| @flashes.delete k }
          @discard.clear
          @discard | @flashes.keys.to_set
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
