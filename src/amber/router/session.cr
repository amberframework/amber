module Amber::Router::Session
  class Store
    getter session_config : Hash(Symbol, Symbol | String | Int32) = Amber::Server.settings.session
    getter cookies : Cookies::Store

    def initialize(@cookies)
    end

    def build : Session::AbstractStore
      return RedisStore.build(redis_store, cookies, session_config) if redis?
      CookieStore.build(cookie_store, session_config)
    end

    private def cookie_store
      if encrypted_cookie?
        cookies.encrypted
      else
        cookies.signed
      end
    end

    private def redis_store
      Redis.new(url: Amber::Server.settings.redis_url.to_s)
    end

    private def redis?
      store == :redis
    end

    private def encrypted_cookie?
      store == "encrypted_cookie"
    end

    private def store
      session_config[:store]
    end

    private def secret
      session_config[:secret]
    end
  end
end
