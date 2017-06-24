module Amber::Router::Session
  # This is the default Cookie Store
  class CookieStore < AbstractStore
    property secret : String
    property key : String
    property expires : Int32
    property store : Amber::Router::Cookies::Store
    property session : Hash(String, String)

    def initialize(@store, @key, @expires, @secret)
      @session = current_session
      @session[key] = SecureRandom.uuid
    end

    def id
      @session[key]
    end

    def destroy
      @session.clear
    end

    def [](key : String | Symbol)
      @session.fetch(key.to_s)
    end

    def []?(key : String | Symbol)
      fetch(key.to_s, nil)
    end

    def []=(key : String | Symbol, value)
      @session[key.to_s] = value.to_s
    end

    def key?(key : String | Symbol)
      @session.has_key?(key.to_s)
    end

    def keys
      @session.keys
    end

    def values
      @session.values
    end

    def to_h
      @session
    end

    def update(hash : Hash(String | Symbol, String))
      hash.each do |key, value|
        @session[key.to_s] = value
      end
      @session
    end

    def delete(key : String | Symbol)
      @session.delete(key.to_s) if key?(key.to_s)
    end

    def fetch(key : String | Symbol, default = nil)
      @session.fetch(key.to_s, default)
    end

    def empty?
      @session.select { |_key, _| _key != key }.empty?
    end

    def set_session
      store.encrypted.set(key, session.to_json, expires: (Time.now + expires.seconds), http_only: true)
    end

    def current_session
      Hash(String, String).from_json(@store.encrypted[key] || "{}")
    rescue e : JSON::ParseException
      Hash(String, String).new
    end
  end
end
