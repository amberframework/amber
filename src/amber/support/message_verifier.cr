require "base64"
require "crypto/subtle"
require "./message_authentication"

module Amber::Support
  # Signs a message so that it can travel through a cookie and come back
  # unchanged: `generate` returns `<base64 of the message>--<base64 of its
  # HMAC tag>`, and `verify` returns the message only when the tag matches.
  #
  # *digest* is `:sha256` (the default), `:sha384` or `:sha512`; `:sha1` is
  # accepted for cookies signed by Amber 1. Messages signed with any of
  # *previous_secrets* still verify, for key rotation.
  class MessageVerifier
    Log = ::Log.for(self)

    getter secret : String
    getter previous_secrets : Array(String)

    @digest : Symbol

    def initialize(@secret : String, digest : Symbol | String = :sha256, @previous_secrets = [] of String)
      @digest = MessageAuthentication.supported_digest_name(digest)
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
      message = argument_error.message
      return if message && message.includes?("invalid base64")
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
          if signed_under?(old_secret, data, digest)
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
        if signed_under?(old_secret, data, digest)
          Log.info { "Message verified with rotated secret key" }
          return String.new(decode(data))
        end
      end
      nil
    end

    private def signed_under?(secret : String, data : String, digest : String) : Bool
      expected_digest = encode(MessageAuthentication.authentication_tag(@digest, secret, data))
      data.size > 0 && digest.size > 0 && Crypto::Subtle.constant_time_compare(digest, expected_digest)
    end

    private def encode(data)
      ::Base64.strict_encode(data)
    end

    private def decode(data)
      ::Base64.decode(data)
    end

    private def generate_digest(data)
      encode(MessageAuthentication.authentication_tag(@digest, @secret, data))
    end
  end
end
