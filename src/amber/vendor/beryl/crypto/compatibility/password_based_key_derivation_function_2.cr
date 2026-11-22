require "../error"
require "../secret_wiping"
require "../v1/hash_based_message_authentication_code"
require "../v1/secure_hash_with_256_bit_digest"
require "../v1/secure_hash_with_512_bit_digest"
require "./secure_hash_algorithm_1"

module Amber::Beryl::Crypto::Compatibility
  # PBKDF2 with HMAC (RFC 8018 §5.2): stretches a password into a key by
  # repeating HMAC *iteration_count* times. `D` is `SHA1`, `V1::SHA256` or
  # `V1::SHA512`.
  #
  # NOTE: PBKDF2 is here for formats that require it, such as PostgreSQL
  # SCRAM-SHA-256 (RFC 7677). It is not the password hash to choose for a
  # new design.
  #
  # ```
  # pbkdf2 = Amber::Beryl::Crypto::Compatibility::PBKDF2(Amber::Beryl::Crypto::V1::SHA256)
  # salted_password = pbkdf2.derive_key("pencil", salt: salt, iteration_count: 4096, bytesize: 32)
  # ```
  module PasswordBasedKeyDerivationFunction2(D)
    # Returns *bytesize* bytes of key derived from *password* and *salt*.
    #
    # Raises `IterationCountTooSmall` when *iteration_count* is under one and
    # `DerivedKeySizeIsNegative` when *bytesize* is negative.
    def self.derive_key(
      password : Bytes | String,
      *,
      salt : Bytes | String,
      iteration_count : Int32,
      bytesize : Int32,
    ) : Bytes
      {% unless D <= SecureHashAlgorithm1 || D <= V1::SecureHashWith256BitDigest || D <= V1::SecureHashWith512BitDigest %}
        {% raise "Beryl's PBKDF2 is built on SHA1, SHA256 or SHA512, not on #{D}" %}
      {% end %}
      if iteration_count < 1
        raise IterationCountTooSmall.new("PBKDF2 runs at least one iteration, not #{iteration_count}")
      end
      if bytesize < 0
        raise DerivedKeySizeIsNegative.new("PBKDF2 was asked for #{bytesize} bytes")
      end

      derived_key = Bytes.new(bytesize)
      authentication = V1::HMAC(D).new(password)
      digest_bytesize = authentication.digest_size
      salt_bytes = salt.to_slice
      chained_storage = uninitialized UInt8[V1::BlockHashFunction::LARGEST_DIGEST_SIZE]
      block_storage = uninitialized UInt8[V1::BlockHashFunction::LARGEST_DIGEST_SIZE]
      chained = chained_storage.to_slice[0, digest_bytesize]
      block = block_storage.to_slice[0, digest_bytesize]
      block_number_bytes = uninitialized UInt8[4]
      block_number = 0_u32
      bytes_written = 0

      # T(n) = U(1) ^ U(2) ^ ... ^ U(c), with U(1) = HMAC(P, salt | INT(n))
      # and U(j) = HMAC(P, U(j - 1)).
      while bytes_written < bytesize
        block_number &+= 1
        IO::ByteFormat::BigEndian.encode(block_number, block_number_bytes.to_slice)
        authentication.reset
        authentication.update(salt_bytes)
        authentication.update(block_number_bytes.to_slice)
        authentication.final(chained)
        chained.copy_to(block)

        (iteration_count - 1).times do
          authentication.reset
          authentication.update(chained)
          authentication.final(chained)
          digest_bytesize.times { |index| block[index] ^= chained[index] }
        end

        bytes_taken = Math.min(digest_bytesize, bytesize - bytes_written)
        block[0, bytes_taken].copy_to(derived_key[bytes_written, bytes_taken])
        bytes_written += bytes_taken
      end

      SecretWiping.wipe(chained_storage.to_slice)
      SecretWiping.wipe(block_storage.to_slice)
      derived_key
    end
  end

  # The common name of `PasswordBasedKeyDerivationFunction2`.
  alias PBKDF2 = PasswordBasedKeyDerivationFunction2
end
