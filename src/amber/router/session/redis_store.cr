require "redis"
require "uuid"

module Amber::Router::Session
  class RedisStore < AbstractStore
    @id : String?
    getter store : Redis
    property expires : Int32
    property key : String
    property session_id : String
    property cookies : Amber::Router::Cookies::Store

    def self.build(store, cookies, session)
      new(store, cookies, session[:key].to_s, session[:expires].to_i)
    end

    def initialize(@store, @cookies, @key, @expires = 120)
      @session_id = current_session || "#{key}:#{id}"
    end

    def id
      @id ||= UUID.random.to_s
    end

    def changed?
      true
    end

    def destroy
      store.del(session_id)
    end

    def [](key : String | Symbol)
      return store.hget(session_id, key.to_s) if has_key?(key.to_s)
      raise KeyError.new "Missing hash key: #{key.inspect}"
    end

    def []?(key : String | Symbol)
      fetch(key.to_s, nil)
    end

    def []=(key : String | Symbol, value)
      store.hset(session_id, key.to_s, value)
    end

    def has_key?(key : String | Symbol) : Bool
      store.hexists(session_id, key.to_s) == 1 ? true : false
    end

    def keys
      store.hkeys(session_id)
    end

    def values
      store.hvals(session_id)
    end

    def to_h
      store.hgetall(session_id).each_slice(2).to_h
    end

    def update(hash : Hash(String | Symbol, String))
      store.hmset(session_id, hash)
    end

    def delete(key : String | Symbol)
      store.hdel(session_id, key.to_s) if has_key?(key.to_s)
    end

    def fetch(key : String | Symbol, default = nil)
      store.hget(session_id, key.to_s) || default
    end

    def empty?
      # 1 since the session id key always gets set technically is never empty
      store.hlen(session_id) <= 1
    end

    def set_session
      cookies.encrypted.set(key, session_id, expires: expires_at, http_only: true)

      store.pipelined do |pipeline|
        pipeline.hset(session_id, key, session_id)
        pipeline.expire(session_id, expires) if expires_at
      end
    end

    def expires_at
      (Time.utc + expires.seconds) if @expires > 0
    end

    def current_session
      cookies.encrypted[key]
    end
  end
end
