require "./secure_hash_with_32_bit_words"

module Amber::Beryl::Crypto::V1
  # SHA-256 (FIPS 180-4 §6.2): a 256-bit digest. This is the hash Beryl
  # recommends and the one `Amber::Beryl::Crypto.digest` uses.
  #
  # ```
  # Amber::Beryl::Crypto::V1::SHA256.hexdigest("abc")
  # # => "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  #
  # hash = Amber::Beryl::Crypto::V1::SHA256.new
  # hash.update("a").update("bc")
  # hash.final # => Bytes[186, 120, 22, ...]
  # ```
  class SecureHashWith256BitDigest < SecureHashWith32BitWords
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 32

    private def initial_state : StaticArray(UInt32, 8)
      StaticArray[
        0x6a09e667_u32, 0xbb67ae85_u32, 0x3c6ef372_u32, 0xa54ff53a_u32,
        0x510e527f_u32, 0x9b05688c_u32, 0x1f83d9ab_u32, 0x5be0cd19_u32,
      ]
    end

    def digest_size : Int32
      DIGEST_SIZE
    end
  end

  # The common name of `SecureHashWith256BitDigest`.
  alias SHA256 = SecureHashWith256BitDigest
end
