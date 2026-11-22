require "./secure_hash_with_64_bit_words"

module Amber::Beryl::Crypto::V1
  # SHA-384 (FIPS 180-4 §6.5): SHA-512's compression function with its own
  # initial state, and a digest cut to 384 bits.
  #
  # ```
  # Amber::Beryl::Crypto::V1::SHA384.hexdigest("abc")
  # # => "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
  # ```
  class SecureHashWith384BitDigest < SecureHashWith64BitWords
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 48

    private def initial_state : StaticArray(UInt64, 8)
      StaticArray[
        0xcbbb9d5dc1059ed8_u64, 0x629a292a367cd507_u64, 0x9159015a3070dd17_u64, 0x152fecd8f70e5939_u64,
        0x67332667ffc00b31_u64, 0x8eb44a8768581511_u64, 0xdb0c2e0d64f98fa7_u64, 0x47b5481dbefa4fa4_u64,
      ]
    end

    def digest_size : Int32
      DIGEST_SIZE
    end
  end

  # The common name of `SecureHashWith384BitDigest`.
  alias SHA384 = SecureHashWith384BitDigest
end
