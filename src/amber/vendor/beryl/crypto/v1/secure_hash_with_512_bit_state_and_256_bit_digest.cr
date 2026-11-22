require "./secure_hash_with_64_bit_words"

module Amber::Beryl::Crypto::V1
  # SHA-512/256 (FIPS 180-4 §6.7): SHA-512's compression function with its
  # own initial state, and a digest cut to 256 bits.
  #
  # ```
  # Amber::Beryl::Crypto::V1::SHA512_256.hexdigest("abc")
  # # => "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23"
  # ```
  class SecureHashWith512BitStateAnd256BitDigest < SecureHashWith64BitWords
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 32

    private def initial_state : StaticArray(UInt64, 8)
      StaticArray[
        0x22312194fc2bf72c_u64, 0x9f555fa3c84c64c2_u64, 0x2393b86b6f53b151_u64, 0x963877195940eabd_u64,
        0x96283ee2a88effe3_u64, 0xbe5e1e2553863992_u64, 0x2b0199fc2c85b8aa_u64, 0x0eb72ddc81c52ca2_u64,
      ]
    end

    def digest_size : Int32
      DIGEST_SIZE
    end
  end

  # The common name of `SecureHashWith512BitStateAnd256BitDigest`.
  alias SHA512_256 = SecureHashWith512BitStateAnd256BitDigest
end
