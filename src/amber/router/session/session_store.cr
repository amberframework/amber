module Amber::Router::Session
  class Store
    getter config : Hash(Symbol, Symbol | String | Int32)
    getter cookies : Cookies::Store

    def initialize(@cookies, @config)
    end

    def build : Session::AbstractStore
      # Use adapter-based sessions by default
      adapter_name = config[:adapter]?.try(&.to_s) || "memory"
      adapter = Amber::Adapters::AdapterFactory.create_session_adapter(adapter_name)
      AdapterSessionStore.build(adapter, cookies, config)
    end

    private def cookie_store
      encrypted_cookie? ? cookies.encrypted : cookies.signed
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
