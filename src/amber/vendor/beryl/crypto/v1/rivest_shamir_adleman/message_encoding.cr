module Amber::Beryl::Crypto::V1::RivestShamirAdleman
  # :nodoc:
  #
  # The encodings of RFC 8017 that sit between a message and the RSA
  # primitive: EMSA-PKCS1-v1_5 (§9.2), EMSA-PSS (§9.1), EME-OAEP (§7.1)
  # and the mask generation function MGF1 (Appendix B.2.1).
  #
  # Each method takes the hash function as a type. The overloads of
  # `digest_info_prefix` and `ensure_secure_hash_2` decide which hashes each
  # scheme accepts, so an unsupported hash is a compile-time error.
  module MessageEncoding
    # The DER encoding of DigestInfo up to the digest (RFC 8017 §9.2, note 1).
    SHA1_DIGEST_INFO_PREFIX       = Bytes[0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14]
    SHA224_DIGEST_INFO_PREFIX     = Bytes[0x30, 0x2d, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x04, 0x05, 0x00, 0x04, 0x1c]
    SHA256_DIGEST_INFO_PREFIX     = Bytes[0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]
    SHA384_DIGEST_INFO_PREFIX     = Bytes[0x30, 0x41, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02, 0x05, 0x00, 0x04, 0x30]
    SHA512_DIGEST_INFO_PREFIX     = Bytes[0x30, 0x51, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03, 0x05, 0x00, 0x04, 0x40]
    SHA512_256_DIGEST_INFO_PREFIX = Bytes[0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x06, 0x05, 0x00, 0x04, 0x20]

    # The hashes Beryl signs with under PKCS #1 v1.5.
    def self.digest_info_prefix(hash_function : SHA224.class) : Bytes
      SHA224_DIGEST_INFO_PREFIX
    end

    def self.digest_info_prefix(hash_function : SHA256.class) : Bytes
      SHA256_DIGEST_INFO_PREFIX
    end

    def self.digest_info_prefix(hash_function : SHA384.class) : Bytes
      SHA384_DIGEST_INFO_PREFIX
    end

    def self.digest_info_prefix(hash_function : SHA512.class) : Bytes
      SHA512_DIGEST_INFO_PREFIX
    end

    def self.digest_info_prefix(hash_function : SHA512_256.class) : Bytes
      SHA512_256_DIGEST_INFO_PREFIX
    end

    # The hashes Beryl verifies under PKCS #1 v1.5: the signing ones and
    # SHA-1, which older certificates still carry.
    def self.verification_digest_info_prefix(hash_function : Compatibility::SHA1.class) : Bytes
      SHA1_DIGEST_INFO_PREFIX
    end

    def self.verification_digest_info_prefix(hash_function : D.class) : Bytes forall D
      digest_info_prefix(hash_function)
    end

    # The hashes PSS accepts: SHA-2 only.
    def self.ensure_secure_hash_2(hash_function : SHA224.class | SHA256.class | SHA384.class | SHA512.class | SHA512_256.class) : Nil
    end

    # The hashes OAEP accepts: SHA-2, and SHA-1 for MySQL's
    # `caching_sha2_password`, which encrypts with OAEP over SHA-1.
    def self.ensure_oaep_hash(hash_function : Compatibility::SHA1.class | SHA224.class | SHA256.class | SHA384.class | SHA512.class | SHA512_256.class) : Nil
    end

    # Returns EMSA-PKCS1-v1_5(digest) of *encoded_bytesize* bytes:
    # 0x00 0x01, 0xff padding, 0x00, then DigestInfo.
    def self.encode_pkcs1(digest_info_prefix : Bytes, digest : Bytes, encoded_bytesize : Int32) : Bytes
      encoded = Bytes.new(encoded_bytesize, 0xff_u8)
      encoded[0] = 0x00_u8
      encoded[1] = 0x01_u8
      digest_info_start = encoded_bytesize - digest_info_prefix.size - digest.size
      encoded[digest_info_start - 1] = 0x00_u8
      digest_info_prefix.copy_to(encoded[digest_info_start, digest_info_prefix.size])
      digest.copy_to(encoded[encoded_bytesize - digest.size, digest.size])
      encoded
    end

    # XORs MGF1(*seed*) into *target*, all of it, hashing with *hash_function*.
    def self.mask_with_mgf1(hash_function : D.class, seed : Bytes, target : Bytes) : Nil forall D
      block_storage = uninitialized UInt8[BlockHashFunction::LARGEST_DIGEST_SIZE]
      block = block_storage.to_slice[0, D::DIGEST_SIZE]
      counter_bytes = uninitialized UInt8[4]
      digest = D.new
      offset = 0
      counter = 0_u32
      while offset < target.size
        IO::ByteFormat::BigEndian.encode(counter, counter_bytes.to_slice)
        digest.reset
        digest.update(seed)
        digest.update(counter_bytes.to_slice)
        digest.final(block)
        piece_bytesize = Math.min(block.size, target.size - offset)
        piece_bytesize.times { |index| target[offset + index] ^= block[index] }
        offset += piece_bytesize
        counter &+= 1
      end
      SecretWiping.wipe(block_storage.to_slice)
    end

    # Returns the EMSA-PSS encoding (RFC 8017 §9.1.1) of a message whose
    # hash is *message_digest*, with *salt*, for an encoded message of
    # *encoded_bit_count* bits (one less than the modulus). Raises
    # `SaltTooLongForModulus` when the hash, the salt and two bytes do not
    # fit.
    def self.encode_pss(hash_function : D.class, message_digest : Bytes, salt : Bytes, encoded_bit_count : Int32) : Bytes forall D
      digest_bytesize = D::DIGEST_SIZE
      encoded_bytesize = (encoded_bit_count + 7) // 8
      if encoded_bytesize < digest_bytesize + salt.size + 2
        raise SaltTooLongForModulus.new("a salt of #{salt.size} bytes does not fit a #{encoded_bit_count}-bit encoding with a #{digest_bytesize}-byte hash")
      end

      salted_hash = pss_salted_hash(hash_function, message_digest, salt)
      encoded = Bytes.new(encoded_bytesize)
      data_block_bytesize = encoded_bytesize - digest_bytesize - 1
      data_block = encoded[0, data_block_bytesize]
      data_block[data_block_bytesize - salt.size - 1] = 0x01_u8
      salt.copy_to(data_block[data_block_bytesize - salt.size, salt.size])
      mask_with_mgf1(hash_function, salted_hash, data_block)
      data_block[0] &= 0xff_u8 >> (8 * encoded_bytesize - encoded_bit_count)
      salted_hash.copy_to(encoded[data_block_bytesize, digest_bytesize])
      encoded[encoded_bytesize - 1] = 0xbc_u8
      encoded
    end

    # Returns whether *encoded* is a valid EMSA-PSS encoding (RFC 8017
    # §9.1.2) of a message whose hash is *message_digest*, with a salt of
    # *salt_bytesize* bytes. Every input here is public.
    def self.pss_encoding_matches?(hash_function : D.class, message_digest : Bytes, encoded : Bytes,
                                   encoded_bit_count : Int32, salt_bytesize : Int32) : Bool forall D
      digest_bytesize = D::DIGEST_SIZE
      encoded_bytesize = encoded.size
      return false if salt_bytesize < 0
      return false if encoded_bytesize < digest_bytesize + salt_bytesize + 2
      return false unless encoded[encoded_bytesize - 1] == 0xbc_u8

      data_block_bytesize = encoded_bytesize - digest_bytesize - 1
      data_block = encoded[0, data_block_bytesize].dup
      salted_hash = encoded[data_block_bytesize, digest_bytesize]
      unused_bit_mask = ~(0xff_u8 >> (8 * encoded_bytesize - encoded_bit_count))
      return false unless data_block[0] & unused_bit_mask == 0

      mask_with_mgf1(hash_function, salted_hash, data_block)
      data_block[0] &= ~unused_bit_mask
      padding_bytesize = data_block_bytesize - salt_bytesize - 1
      return false unless data_block[0, padding_bytesize].all?(&.zero?)
      return false unless data_block[padding_bytesize] == 0x01_u8

      salt = data_block[data_block_bytesize - salt_bytesize, salt_bytesize]
      pss_salted_hash(hash_function, message_digest, salt) == salted_hash
    end

    # H(0x00 × 8 || mHash || salt).
    private def self.pss_salted_hash(hash_function : D.class, message_digest : Bytes, salt : Bytes) : Bytes forall D
      digest = D.new
      digest.update(Bytes.new(8))
      digest.update(message_digest)
      digest.update(salt)
      digest.final
    end

    # Returns the EME-OAEP encoding (RFC 8017 §7.1.1 step 2) of *message*,
    # *encoded_bytesize* bytes long, with *seed* (as long as the hash).
    def self.encode_oaep(hash_function : D.class, message : Bytes, label_digest : Bytes, seed : Bytes,
                         encoded_bytesize : Int32) : Bytes forall D
      digest_bytesize = D::DIGEST_SIZE
      encoded = Bytes.new(encoded_bytesize)
      masked_seed = encoded[1, digest_bytesize]
      data_block = encoded[1 + digest_bytesize, encoded_bytesize - digest_bytesize - 1]
      label_digest.copy_to(data_block[0, digest_bytesize])
      data_block[data_block.size - message.size - 1] = 0x01_u8
      message.copy_to(data_block[data_block.size - message.size, message.size])
      seed.copy_to(masked_seed)
      mask_with_mgf1(hash_function, masked_seed, data_block)
      mask_with_mgf1(hash_function, data_block, masked_seed)
      encoded
    end

    # Decodes the EME-OAEP encoding in *encoded* in place (RFC 8017 §7.1.2
    # step 3), in time that depends only on the sizes, after BearSSL's
    # `rsa_oaep_unpad.c`. Returns the message length plus one when the
    # encoding is well formed and *is_in_range* is 1, and 0 otherwise; the
    # message is then the last bytes of *encoded*. Every malformed encoding
    # gives the same 0, whatever was wrong with it.
    def self.decode_oaep(hash_function : D.class, encoded : Bytes, label_digest : Bytes, is_in_range : UInt64) : UInt32 forall D
      digest_bytesize = D::DIGEST_SIZE
      masked_seed = encoded[1, digest_bytesize]
      data_block = encoded[1 + digest_bytesize, encoded.size - digest_bytesize - 1]
      mask_with_mgf1(hash_function, data_block, masked_seed)
      mask_with_mgf1(hash_function, masked_seed, data_block)

      is_well_formed = is_in_range.to_u32! & zero_bit_of(encoded[0].to_u32)
      label_difference = 0_u32
      digest_bytesize.times { |index| label_difference |= (data_block[index] ^ label_digest[index]).to_u32 }
      is_well_formed &= zero_bit_of(label_difference)

      # The first byte after the label digest that is not zero must be 0x01.
      is_found = 0_u32
      is_malformed = 0_u32
      separator_index = 0_u32
      (digest_bytesize...data_block.size).each do |index|
        byte = data_block[index].to_u32
        is_zero = zero_bit_of(byte)
        is_one = zero_bit_of(byte ^ 1_u32)
        is_before_separator = is_found ^ 1_u32
        separator_index |= index.to_u32 & (0_u32 &- (is_before_separator & is_one))
        is_malformed |= is_before_separator & ((is_zero | is_one) ^ 1_u32)
        is_found |= is_one
      end
      is_well_formed &= is_found & (is_malformed ^ 1_u32)

      message_bytesize = data_block.size.to_u32 &- 1_u32 &- separator_index
      (message_bytesize &+ 1_u32) & (0_u32 &- is_well_formed)
    end

    # Returns 1 when *value* is zero, and 0 otherwise.
    @[AlwaysInline]
    private def self.zero_bit_of(value : UInt32) : UInt32
      ((value | (0_u32 &- value)) >> 31) ^ 1_u32
    end
  end
end
