require "./*"
require "http"
require "../../support/*"

module Amber::Router::Cookies
  class SignedStore < AbstractStore
    def initialize(@store, secret)
      @verifier = Support::MessageVerifier.new(secret)
    end

    def get(name)
      if value = @store.get(name)
        verify(value)
      end
    end

    def set(name : String, value : String, path : String = "/", expires : Time? = nil, domain : String? = nil, secure : Bool = false, http_only : Bool = false, extension : String? = nil)
      cookie = HTTP::Cookie.new(name, @verifier.generate(value), path, expires, domain, secure, http_only, extension)
      raise Exceptions::CookieOverflow.new if cookie.value.bytesize > MAX_COOKIE_SIZE
      @store[name] = cookie
    end

    private def verify(message)
      @verifier.verify(message)
    rescue e # TODO: This should probably actually raise the exception instead of rescuing from it.
      ""
    end
  end
end
