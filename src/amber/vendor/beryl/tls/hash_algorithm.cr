require "../crypto"

module Amber::Beryl::TLS
  # The two hashes a TLS 1.3 key schedule runs on (RFC 9846 §7.1): SHA-256
  # for the AES-128-GCM and ChaCha20-Poly1305 suites, SHA-384 for
  # AES-256-GCM. Each call goes to Beryl's own SHA-2, HMAC and HKDF.
  enum HashAlgorithm
    SHA256
    SHA384

    # The digest size in bytes.
    def bytesize : Int32
      sha256? ? 32 : 48
    end

    # Returns the hash of *message*.
    def digest(message : Bytes) : Bytes
      sha256? ? Crypto::V1::SHA256.digest(message) : Crypto::V1::SHA384.digest(message)
    end

    # Returns HMAC of *message* under *key*.
    def authenticate(message : Bytes, *, key : Bytes) : Bytes
      if sha256?
        Crypto::V1::HMAC(Crypto::V1::SHA256).authenticate(message, key: key)
      else
        Crypto::V1::HMAC(Crypto::V1::SHA384).authenticate(message, key: key)
      end
    end

    # Returns whether *tag* is HMAC of *message* under *key*, compared in
    # constant time.
    def verify(message : Bytes, tag : Bytes, *, key : Bytes) : Bool
      if sha256?
        Crypto::V1::HMAC(Crypto::V1::SHA256).verify(message, tag, key: key)
      else
        Crypto::V1::HMAC(Crypto::V1::SHA384).verify(message, tag, key: key)
      end
    end

    # HKDF-Extract (RFC 5869 §2.2).
    def extract(input_key_material : Bytes, *, salt : Bytes) : Bytes
      if sha256?
        Crypto::V1::HKDF(Crypto::V1::SHA256).extract(input_key_material, salt: salt)
      else
        Crypto::V1::HKDF(Crypto::V1::SHA384).extract(input_key_material, salt: salt)
      end
    end

    # HKDF-Expand (RFC 5869 §2.3).
    def expand(pseudorandom_key : Bytes, *, info : Bytes, bytesize : Int32) : Bytes
      if sha256?
        Crypto::V1::HKDF(Crypto::V1::SHA256).expand(pseudorandom_key, info: info, bytesize: bytesize)
      else
        Crypto::V1::HKDF(Crypto::V1::SHA384).expand(pseudorandom_key, info: info, bytesize: bytesize)
      end
    end

    # Returns the hash of the empty string.
    def empty_digest : Bytes
      digest(Bytes.empty)
    end
  end
end
