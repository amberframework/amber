require "./secure_hash_with_64_bit_words"

module Amber::Beryl::Crypto::V1
  # SHA-512 (FIPS 180-4 §6.4): a 512-bit digest.
  #
  # ```
  # Amber::Beryl::Crypto::V1::SHA512.hexdigest("abc")
  # # => "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
  # ```
  class SecureHashWith512BitDigest < SecureHashWith64BitWords
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 64

    private def initial_state : StaticArray(UInt64, 8)
      StaticArray[
        0x6a09e667f3bcc908_u64, 0xbb67ae8584caa73b_u64, 0x3c6ef372fe94f82b_u64, 0xa54ff53a5f1d36f1_u64,
        0x510e527fade682d1_u64, 0x9b05688c2b3e6c1f_u64, 0x1f83d9abfb41bd6b_u64, 0x5be0cd19137e2179_u64,
      ]
    end

    def digest_size : Int32
      DIGEST_SIZE
    end
  end

  # The common name of `SecureHashWith512BitDigest`.
  alias SHA512 = SecureHashWith512BitDigest
end
