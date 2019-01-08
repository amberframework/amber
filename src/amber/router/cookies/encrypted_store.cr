require "http"
require "../../support/*"

module Amber::Router::Cookies
  class EncryptedStore < AbstractStore
    def initialize(@store, secret)
      @encryptor = Support::MessageEncryptor.new(secret, digest: :sha256)
    end

    def get(name)
      if value = @store.get(name)
        verify_and_decrypt(value)
      end
    end

    def set(name : String, value : String, path : String = "/", expires : Time? = nil,
            domain : String? = nil, secure : Bool = false,
            http_only : Bool = false, extension : String? = nil)
      cookie = HTTP::Cookie.new(name, Base64.strict_encode(@encryptor.encrypt(value, sign: true)),
        path, expires, domain, secure, http_only, extension)
      raise Exceptions::CookieOverflow.new if cookie.value.bytesize > MAX_COOKIE_SIZE
      @store[name] = cookie
    end

    private def verify_and_decrypt(encrypted_message)
      String.new(@encryptor.verify_and_decrypt(Base64.decode(encrypted_message)))
    rescue e # TODO: This should probably actually raise the exception instead of rescuing from it.
      ""
    end
  end
end
