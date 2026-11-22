require "../error"
require "../secret_wiping"
require "./hash_based_message_authentication_code"
require "./secure_hash_with_256_bit_digest"
require "./secure_hash_with_384_bit_digest"
require "./secure_hash_with_512_bit_digest"
require "../compatibility/secure_hash_algorithm_1"

module Amber::Beryl::Crypto::V1
  # HKDF (RFC 5869): turns key material that is secret but uneven, such as a
  # shared secret from a key exchange, into as many independent keys as a
  # protocol needs. `D` is `SHA256`, `SHA384` or `SHA512`; `Compatibility::SHA1`
  # is accepted for formats that already use it.
  #
  # ```
  # hkdf = Amber::Beryl::Crypto::V1::HKDF(Amber::Beryl::Crypto::V1::SHA256)
  # key = hkdf.derive_key(shared_secret, salt: salt, info: "session cookies", bytesize: 32)
  # ```
  #
  # `derive_key` is the whole function. `extract` and `expand` are its two
  # steps, for protocols such as TLS 1.3 that call them separately.
  module HashBasedKeyDerivationFunction(D)
    # RFC 5869 §2.3 counts output blocks in one byte.
    MAXIMUM_BLOCK_COUNT = 255

    # Returns the pseudorandom key (one hash output long) concentrated from
    # *input_key_material*. An empty *salt* stands for a string of zeros one
    # hash output long, as RFC 5869 §2.2 defines.
    def self.extract(input_key_material : Bytes | String, *, salt : Bytes | String = Bytes.empty) : Bytes
      ensure_the_hash_is_supported
      HMAC(D).authenticate(input_key_material, key: salt)
    end

    # Returns *bytesize* bytes of key derived from *pseudorandom_key*, which
    # should be one hash output long (the result of `extract`). *info* names
    # the purpose, so that different purposes get unrelated keys.
    #
    # Raises `DerivedKeyTooLong` when *bytesize* is over 255 hash outputs.
    def self.expand(pseudorandom_key : Bytes | String, *, info : Bytes | String = Bytes.empty, bytesize : Int32) : Bytes
      ensure_the_hash_is_supported
      if bytesize < 0
        raise DerivedKeySizeIsNegative.new("HKDF was asked for #{bytesize} bytes")
      end
      authentication = HMAC(D).new(pseudorandom_key)
      digest_bytesize = authentication.digest_size
      maximum_bytesize = MAXIMUM_BLOCK_COUNT * digest_bytesize
      if bytesize > maximum_bytesize
        raise DerivedKeyTooLong.new("HKDF on this hash gives at most #{maximum_bytesize} bytes, not #{bytesize}")
      end

      derived_key = Bytes.new(bytesize)
      block_storage = uninitialized UInt8[BlockHashFunction::LARGEST_DIGEST_SIZE]
      block = block_storage.to_slice[0, digest_bytesize]
      info_bytes = info.to_slice
      block_number = StaticArray[0_u8]
      bytes_written = 0

      # T(n) = HMAC(PRK, T(n - 1) | info | n), with T(0) empty.
      while bytes_written < bytesize
        authentication.reset
        authentication.update(block) if block_number[0] > 0
        block_number[0] &+= 1
        authentication.update(info_bytes)
        authentication.update(block_number.to_slice)
        authentication.final(block)

        bytes_taken = Math.min(digest_bytesize, bytesize - bytes_written)
        block[0, bytes_taken].copy_to(derived_key[bytes_written, bytes_taken])
        bytes_written += bytes_taken
      end

      SecretWiping.wipe(block_storage.to_slice)
      derived_key
    end

    # Returns *bytesize* bytes of key derived from *input_key_material*:
    # `extract`, then `expand`.
    def self.derive_key(
      input_key_material : Bytes | String,
      *,
      salt : Bytes | String = Bytes.empty,
      info : Bytes | String = Bytes.empty,
      bytesize : Int32,
    ) : Bytes
      pseudorandom_key = extract(input_key_material, salt: salt)
      derived_key = expand(pseudorandom_key, info: info, bytesize: bytesize)
      SecretWiping.wipe(pseudorandom_key)
      derived_key
    end

    # Stops compilation when `D` is a hash this function is not offered on.
    private def self.ensure_the_hash_is_supported : Nil
      {% unless D <= SecureHashWith256BitDigest || D <= SecureHashWith384BitDigest || D <= SecureHashWith512BitDigest || D <= Compatibility::SecureHashAlgorithm1 %}
        {% raise "Beryl HKDF is built on SHA256, SHA384, SHA512 or Compatibility::SHA1, not on #{D}" %}
      {% end %}
    end
  end

  # The common name of `HashBasedKeyDerivationFunction`.
  alias HKDF = HashBasedKeyDerivationFunction
end
