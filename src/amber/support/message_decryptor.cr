require "json"
require "openssl/hmac"
require "crypto/subtle"

module Amber::Support
  class MessageVerifier
    def initialize(@secret : Bytes, @digest = :sha1)
    end

    def valid_message?(signed_message)
      splitted = signed_message.to_s.split("--", 2)
      return if splitted.size < 2
      data, digest = splitted
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, generate_digest(data))
    end

    def verified(signed_message : String)
      if valid_message?(signed_message)
        begin
          data = signed_message.split("--")[0]
          String.new(decode(data))
        rescue argument_error : ArgumentError
          return if argument_error.message =~ %r{invalid base64}
          raise argument_error
        end
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
