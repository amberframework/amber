require "../constant_time_selection"
require "../declassification"
require "../secret_wiping"
require "./hash_based_message_authentication_code"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # The deterministic ECDSA nonce of RFC 6979 §3.2: HMAC_DRBG over the hash
  # *D*, seeded with the private key and the message digest. The same key
  # and digest always give the same nonce, so a signature never depends on
  # the quality of a random number generator.
  #
  # Every candidate is a secret. The one decision taken on it, whether it
  # lies in [1, n - 1], goes through `Declassification.reveal`: a rejected
  # candidate is discarded, so the verdict says nothing about the nonce that
  # is used (rejection has probability below 2^-32 for P-256 and P-384).
  struct DeterministicSignatureNonce(D)
    # The one-byte separators of steps d, f and h.3.
    SEPARATOR_ZERO = Bytes[0x00]
    SEPARATOR_ONE  = Bytes[0x01]

    # Returns the nonce k for *private_scalar* and *digest_integer* (both
    # big-endian, `group_order.size` bytes, the digest already reduced
    # modulo n as bits2octets requires).
    def self.generate(private_scalar : Bytes, digest_integer : Bytes, group_order : Bytes) : Bytes
      hash_bytesize = D.new.digest_size
      value = Bytes.new(hash_bytesize, 0x01_u8)
      key = Bytes.new(hash_bytesize, 0x00_u8)

      key = HMAC(D).new(key).update(value).update(SEPARATOR_ZERO).update(private_scalar).update(digest_integer).final
      value = HMAC(D).new(key).update(value).final
      key = HMAC(D).new(key).update(value).update(SEPARATOR_ONE).update(private_scalar).update(digest_integer).final
      # Every HMAC under one K reuses the authentication keyed with it.
      keyed = HMAC(D).new(key)
      value = keyed.update(value).final

      candidate = Bytes.new(group_order.size)
      loop do
        filled = 0
        while filled < candidate.size
          value = keyed.reset.update(value).final
          taken = Math.min(value.size, candidate.size - filled)
          value[0, taken].copy_to(candidate[filled, taken])
          filled += taken
        end
        # Both curves' orders fill whole bytes, so bits2int is the leading
        # bytes as they are.
        is_nonzero = ConstantTimeSelection.all_zero_bit(candidate) ^ 1_u64
        is_below_order = ConstantTimeSelection.big_endian_less_than_bit(candidate, group_order)
        if Declassification.reveal((is_nonzero & is_below_order) == 1_u64)
          SecretWiping.wipe(key)
          SecretWiping.wipe(value)
          return candidate
        end

        key = HMAC(D).new(key).update(value).update(SEPARATOR_ZERO).final
        keyed = HMAC(D).new(key)
        value = keyed.update(value).final
      end
    end
  end
end
