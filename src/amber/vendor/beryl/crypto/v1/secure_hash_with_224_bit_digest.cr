require "./secure_hash_with_32_bit_words"

module Amber::Beryl::Crypto::V1
  # SHA-224 (FIPS 180-4 §6.3): SHA-256's compression function with its own
  # initial state, and a digest cut to 224 bits.
  #
  # ```
  # Amber::Beryl::Crypto::V1::SHA224.hexdigest("abc")
  # # => "23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7"
  # ```
  class SecureHashWith224BitDigest < SecureHashWith32BitWords
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 28

    private def initial_state : StaticArray(UInt32, 8)
      StaticArray[
        0xc1059ed8_u32, 0x367cd507_u32, 0x3070dd17_u32, 0xf70e5939_u32,
        0xffc00b31_u32, 0x68581511_u32, 0x64f98fa7_u32, 0xbefa4fa4_u32,
      ]
    end

    def digest_size : Int32
      DIGEST_SIZE
    end
  end

  # The common name of `SecureHashWith224BitDigest`.
  alias SHA224 = SecureHashWith224BitDigest
end
