module Amber::Router::Session
  # Builds the session store that `session.store` names.
  #
  # - `signed_cookie` and `encrypted_cookie` keep the whole session in the
  #   visitor's cookie (`CookieStore`); the server holds nothing for it.
  # - `adapter` keeps the session on the server through the adapter that
  #   `session.adapter` names (`AdapterSessionStore`), and the cookie carries
  #   only the encrypted session id. `redis` is read the same way.
  class Store
    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      if keeps_sessions_on_the_server?
        AdapterSessionStore.build(session_adapter, cookies, config)
      else
        CookieStore.build(cookie_store, config)
      end
    end

    private def keeps_sessions_on_the_server? : Bool
      store == :adapter || store == :redis
    end

    private def session_adapter : Amber::Adapters::SessionAdapter
      adapter_name = config[:adapter]?.try(&.to_s) || "memory"
      Amber::Adapters::AdapterFactory.create_session_adapter(adapter_name)
    end

    # A `Cookies::Store` subclass may override `#encrypted`, so its result is
    # checked before the session is kept in it.
    private def cookie_store : Cookies::SignedStore | Cookies::EncryptedStore
      return cookies.signed unless encrypted_cookie?

      encrypted_store = cookies.encrypted
      unless encrypted_store.is_a?(Cookies::EncryptedStore)
        raise Amber::Exceptions::ConfigurationError.new(
          "session.store is encrypted_cookie, but #{cookies.class}#encrypted does not return an Amber::Router::Cookies::EncryptedStore"
        )
      end
      encrypted_store
    end

    private def encrypted_cookie? : Bool
      store == :encrypted_cookie
    end

    private def store
      config[:store]?
    end
  end
end
