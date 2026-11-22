require "../vendor/beryl/crypto"

module Amber::Support
  # The keyed digests (HMAC) Amber signs messages with: `:sha256` (the
  # default), `:sha384` and `:sha512`, plus `:sha1` for an app that still
  # verifies cookies signed by Amber 1, whose default it was. The set is
  # closed so that a build carries these and nothing else.
  module MessageAuthentication
    LIST_OF_DIGEST_NAMES = [:sha256, :sha384, :sha512, :sha1]

    # Returns *digest_name* as one of `LIST_OF_DIGEST_NAMES`, accepting a
    # Symbol or a String in any letter case (`"SHA256"`). Raises
    # `ArgumentError` naming the supported digests for anything else.
    def self.supported_digest_name(digest_name : Symbol | String) : Symbol
      normalized_name = digest_name.to_s.downcase.delete('-')
      supported_name = LIST_OF_DIGEST_NAMES.find { |candidate| candidate.to_s == normalized_name }
      return supported_name if supported_name

      raise ArgumentError.new(
        "Amber signs messages with #{LIST_OF_DIGEST_NAMES.map(&.inspect).join(", ")}; #{digest_name.inspect} is not one of them"
      )
    end

    # Returns the number of bytes in a tag of *digest_name*.
    def self.tag_bytesize(digest_name : Symbol) : Int32
      if digest_name == :sha512
        64
      elsif digest_name == :sha384
        48
      elsif digest_name == :sha1
        20
      else
        32
      end
    end

    # Returns the HMAC tag of *message* under *key*.
    def self.authentication_tag(digest_name : Symbol, key : String | Bytes, message : String | Bytes) : Bytes
      if digest_name == :sha512
        Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::V1::SHA512).authenticate(message, key: key)
      elsif digest_name == :sha384
        Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::V1::SHA384).authenticate(message, key: key)
      elsif digest_name == :sha1
        Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::Compatibility::SHA1).authenticate(message, key: key)
      else
        Amber::Beryl::Crypto::V1::HMAC(Amber::Beryl::Crypto::V1::SHA256).authenticate(message, key: key)
      end
    end
  end
end
