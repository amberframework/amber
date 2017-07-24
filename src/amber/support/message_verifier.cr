require "openssl/hmac"
require "crypto/subtle"

module Amber::Support
  class MessageVerifier
    def initialize(@secret : Bytes, @digest = :sha1)
    end

    def valid_message?(data, digest)
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, generate_digest(data))
    end

    def verified(signed_message : String)
      begin
        data, digest = signed_message.split("--")
        if valid_message?(data, digest)
          String.new(decode(data))
        end
      rescue argument_error : ArgumentError
        return if argument_error.message =~ %r{invalid base64}
        raise argument_error
      end
    end

    def verify(signed_message) : String
      verified(signed_message) || raise(Exceptions::InvalidSignature.new)
    end

    def generate(value : String)
      data = encode(value)
      "#{data}--#{generate_digest(data)}"
    end

    private def encode(data)
      ::Base64.strict_encode(data)
    end

    private def decode(data)
      ::Base64.decode(data)
    end

    private def generate_digest(data)
      OpenSSL::HMAC.hexdigest(@digest, @secret, data)
    end
  end
end
