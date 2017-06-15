require "http"
require "../support/*"

# Defines a betterr cookie store for the request
# The cookies being read are the ones received along with the request,
# the cookies being written will be sent out with the response.
# Reading a cookie does not get the cookie object itself back, just the value it holds.
module Amber::Router
  class Cookies
    module ChainedStore
      @options = {} of String => String

      def permanent
        @permanent ||= PermanentStore.new(self, @key_generator, @options)
      end

      def encrypted
        @encrypted ||= EncryptedStore.new(self, @key_generator, @options)
      end
    end

    # Cookies can typically store 4096 bytes.
    MAX_COOKIE_SIZE = 4096

    class Store
      include Enumerable(String)
      include ChainedStore

      getter cookies
      property host : String?
      property secure : Bool = false

      @key_generator : Support::CachingKeyGenerator

      def initialize(@key_generator, @host = nil, @secure = false)
        @cookies = {} of String => String
        @set_cookies = {} of String => HTTP::Cookie
        @delete_cookies = {} of String => HTTP::Cookie
      end

      def self.from_headers(headers)
        cookies = {} of String => HTTP::Cookie
        if values = headers.get?("Cookie")
          values.each do |header|
            HTTP::Cookie::Parser.parse_cookies(header) do |cookie|
              cookies[cookie.name] = cookie
            end
          end
        end
        cookies
      end

      def self.build(request, key_generator = Support::KeyGenerator.new("secret"))
        headers = request.headers
        host = request.host
        secure = (headers["HTTPS"]? == "on")

        new(key_generator, host, secure).tap do |store|
          store.update(from_headers(headers))
        end
      end

      def update(cookies)
        cookies.each do |name, cookie|
          @cookies[name] = cookie.value
        end
      end

      def each(&block : T -> _)
        @cookies.values.each do |cookie|
          yield cookie
        end
      end

      def each
        @cookies.each_value
      end

      def [](name)
        get(name)
      end

      def get(name)
        @cookies[name]?
      end

      def set(name : String, value : String, path : String = "/",
              expires : Time? = nil, domain : String? = nil,
              secure : Bool = false, http_only : Bool = false,
              extension : String? = nil)
        if @cookies[name]? != value || expires
          @cookies[name] = value
          @set_cookies[name] = HTTP::Cookie.new(name, value, path, expires, domain, secure, http_only, extension)
          @delete_cookies.delete(name) if @delete_cookies.has_key?(name)
        end
      end

      def delete(name : String, path = "/", domain : String? = nil)
        return unless @cookies.has_key?(name)

        value = @cookies.delete(name)
        @delete_cookies[name] = HTTP::Cookie.new(name, "", path, Time.epoch(0), domain)
        value
      end

      def deleted?(name)
        @delete_cookies.has_key?(name)
      end

      def []=(name, value)
        set(name, value)
      end

      def []=(name, cookie : HTTP::Cookie)
        @cookies[name] = cookie.value
        @set_cookies[name] = cookie
      end

      def write(headers)
        cookies = [] of String
        @set_cookies.each { |name, cookie| cookies << cookie.to_set_cookie_header if write_cookie?(cookie) }
        @delete_cookies.each { |name, cookie| cookies << cookie.to_set_cookie_header }
        headers.add("Set-Cookie", cookies)
      end

      def write_cookie?(cookie)
        @secure || !cookie.secure
      end
    end

    class JsonSerializer
      def self.load(value)
        JSON.parse(value)
      end

      def self.dump(value)
        value.to_json
      end
    end

    module SerializedStore
      protected def serialize(name, value)
        serializer.dump(value)
      end

      protected def deserialize(name, value)
        serializer.load(value)["value"].to_s
      end

      protected def serializer
        JsonSerializer
      end

      protected def digest
        :sha256
      end
    end

    class PermanentStore
      include ChainedStore
      getter store : Store
      getter key_generator : Support::CachingKeyGenerator
      getter options : Hash(String, String)

      def initialize(@store, @key_generator, @options)
      end

      def [](name)
        get(name)
      end

      def get(name)
        @store.get(name)
      end

      def []=(name, value)
        set(name, value)
      end

      def set(name : String, value : String, path : String = "/", domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
        cookie = HTTP::Cookie.new(name, value, path, 20.years.from_now, domain, secure, http_only, extension)
        @store[name] = cookie
      end
    end

    class EncryptedStore
      include ChainedStore
      include SerializedStore

      getter store : Store
      getter key_generator : Support::CachingKeyGenerator
      getter options : Hash(String, String)

      def initialize(@store, @key_generator, @options)
        secret = key_generator.generate_key("encrypted_cookie_salt")
        sign_secret = key_generator.generate_key("encrypted_signed_cookie_salt")
        @encryptor = Support::MessageEncryptor.new(secret, sign_secret: sign_secret, digest: digest)
      end

      def [](name)
        get(name)
      end

      def []=(name, value)
        set(name, value)
      end

      def get(name)
        if value = @store.get(name)
          deserialize name, decrypt_and_verify(value)
        end
      end

      def set(name : String, value : String, path : String = "/", expires : Time? = nil, domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
        cookie = HTTP::Cookie.new(name, value, path, expires, domain, secure, http_only, extension)
        cookie.value = @encryptor.encrypt_and_sign(serialize(name, {"value": cookie.value}))
        raise Exceptions::CookieOverflow.new if cookie.value.bytesize > MAX_COOKIE_SIZE
        @store[name] = cookie
      end

      private def decrypt_and_verify(encrypted_message)
        String.new(@encryptor.decrypt_and_verify(encrypted_message))
      rescue e
        "{\"value\":\"\"}"
      end
    end
  end
end
