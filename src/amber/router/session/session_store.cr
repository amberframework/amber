module Amber::Router::Session
  class Store
    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      return RedisStore.build(redis_store, cookies, config) if redis?
      CookieStore.build(cookie_store, config)
    end

    private def cookie_store
      encrypted_cookie? ? cookies.encrypted : cookies.signed
    end

    private def redis_store
      Redis.new(url: Amber.settings.redis_url)
    end

    private def redis?
      store == :redis
    end

    private def encrypted_cookie?
      store == :encrypted_cookie
    end

    private def store
      config[:store]
    end

    private def secret
      config[:secret]
    end
  end
end
