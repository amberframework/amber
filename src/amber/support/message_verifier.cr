require "openssl/hmac"
require "crypto/subtle"

module Amber::Support
  class MessageVerifier
    Log = ::Log.for(self)

    getter secret : String
    getter previous_secrets : Array(String)

    def initialize(@secret : String, @digest = :sha256, @previous_secrets = [] of String)
    end

    def valid_message?(data, digest)
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, generate_digest(data))
    end

    def verified(signed_message : String)
      data, digest = signed_message.split("--")
      if valid_message?(data, digest)
        String.new(decode(data))
      else
        # Try previous secrets for key rotation support
        try_previous_secrets(data, digest)
      end
    rescue argument_error : ArgumentError
      return if argument_error.message =~ %r{invalid base64}
      raise argument_error
    end

    def verify(signed_message) : String
      verified(signed_message) || raise(Exceptions::InvalidSignature.new)
    end

    def verify_raw(signed_message : String) : Bytes
      data, digest = signed_message.split("--")
      if valid_message?(data, digest)
        decode(data)
      else
        # Try previous secrets for key rotation support
        @previous_secrets.each do |old_secret|
          old_digest = encode(OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(@digest.to_s), old_secret, data))
          if data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, old_digest)
            Log.info { "Message verified with rotated secret key" }
            return decode(data)
          end
        end
        raise(Exceptions::InvalidSignature.new)
      end
    end

    def generate(value : String | Bytes)
      data = encode(value)
      "#{data}--#{generate_digest(data)}"
    end

    private def try_previous_secrets(data : String, digest : String) : String?
      @previous_secrets.each do |old_secret|
        old_digest = encode(OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(@digest.to_s), old_secret, data))
        if data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, old_digest)
          Log.info { "Message verified with rotated secret key" }
          return String.new(decode(data))
        end
      end
      nil
    end

    private def encode(data)
      ::Base64.strict_encode(data)
    end

    private def decode(data)
      ::Base64.decode(data)
    end

    private def generate_digest(data)
      encode(OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(@digest.to_s), @secret, data))
    end
  end
end
