require "./*"
require "http"
require "../../support/*"

module Amber::Router::Cookies
  class SignedStore < AbstractStore
    Log = ::Log.for(self)

    def initialize(@store, secret, previous_secrets : Array(String) = [] of String)
      @verifier = Support::MessageVerifier.new(secret, previous_secrets: previous_secrets)
    end

    def get(name)
      if value = @store.get(name)
        verify(value)
      end
    end

    def set(name : String, value : String, path : String = "/",
            expires : Time? = nil, domain : String? = nil,
            secure : Bool = false, http_only : Bool = false,
            extension : String? = nil,
            samesite : HTTP::Cookie::SameSite? = nil)
      cookie = HTTP::Cookie.new(name, @verifier.generate(value), path, expires, domain, secure, http_only, extension)
      cookie.samesite = samesite
      raise Exceptions::CookieOverflow.new if cookie.value.bytesize > MAX_COOKIE_SIZE
      @store[name] = cookie
    end

    private def verify(message)
      @verifier.verify(message)
    rescue e : Exception
      Log.warn { "Failed to verify signed cookie: #{e.message}" }
      nil
    end
  end
end
