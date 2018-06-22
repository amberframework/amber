module Amber::Router::Session
  class Store
    STORES = {
      :redis => RedisStore,
      :encrypted_cookie => CookieStore,
      :signed_cookie => CookieStore
    }

    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      STORES[store].build(cookies_store, config)
    end

    private def cookies_store
      signed_cookie? ? cookies.signed : cookies.encrypted
    end

    private def signed_cookie?
      store == :signed_cookie
    end

    private def store
      config[:store]
    end
  end
end
