module Amber::Router::Session
  class SessionHash < Hash(String, String)
    property changed = false

    def []=(key : String | Symbol, value : V)
      if @changed = (value != fetch(key.to_s, nil))
        super(key.to_s, value)
      end
    end

    def [](key)
      fetch(key.to_s, nil)
    end

    def find_entry(key)
      super(key.to_s)
    end
  end

  # This is the default Cookie Store
  class CookieStore < AbstractStore
    property secret : String
    property key : String
    property expires : Int32
    property store : Amber::Router::Cookies::SignedStore | Amber::Router::Cookies::EncryptedStore
    property session : SessionHash

    forward_missing_to session

    def initialize(@store, @key, @expires, @secret)
      @session = current_session
    end

    def id
      session["id"] ||= SecureRandom.uuid
    end

    def changed?
      session.changed
    end

    def destroy
      session.clear
    end

    def update(hash : Hash(String | Symbol, String))
      hash.each { |key, value| session[key.to_s] = value }
      session
    end

    def set_session
      store.set(key, session.to_json, expires: expires_at, http_only: true)
    end

    def expires_at
      (Time.now + expires.seconds) if @expires > 0
    end

    def current_session
      SessionHash.from_json(store[key] || "{}")
    rescue e : JSON::ParseException
      SessionHash.new
    end
  end
end
