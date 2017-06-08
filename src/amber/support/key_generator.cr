require "openssl/pkcs5"

module Amber::Support
  class KeyGenerator
    def initialize(@secret : String, @iterations : Int32 = 2**16)
    end

    def generate_key(salt, key_size = 64)
      OpenSSL::PKCS5.pbkdf2_hmac_sha1(@secret, salt, @iterations, key_size)
    end
  end

  class CachingKeyGenerator
    def initialize(@key_generator : KeyGenerator)
      @cache_keys = {} of String => Slice(UInt8)
    end

    def generate_key(salt, key_size = 64)
      @cache_keys["#{salt}#{key_size}"] ||= @key_generator.generate_key(salt, key_size)
    end
  end
end
