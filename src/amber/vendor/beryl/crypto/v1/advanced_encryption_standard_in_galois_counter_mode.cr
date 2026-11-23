require "./authenticated_encryption"
require "./bitsliced_advanced_encryption_standard"
require "./galois_hash"
require "./galois_counter_mode_with_processor_instructions"

module Amber::Beryl::Crypto::V1
  # AES-GCM (FIPS 197 and NIST SP 800-38D): authenticated encryption under a
  # 16, 24 or 32-byte key. It is the cipher of TLS 1.3's
  # `TLS_AES_128_GCM_SHA256` and `TLS_AES_256_GCM_SHA384`.
  #
  # ```
  # cipher = Amber::Beryl::Crypto::V1::AESGCM.new(key) # AES-256-GCM for a 32-byte key
  # sealed = cipher.encrypt(body, nonce: nonce, associated_data: header)
  # cipher.decrypt(sealed, nonce: nonce, associated_data: header) # => body, or nil
  # ```
  #
  # Use a 12-byte nonce, and count it: one repeated nonce under one key
  # gives away the authentication key. A nonce of another length is
  # accepted, as the standard defines, for formats that already use one.
  #
  # On a processor with AES and carry-less multiply instructions (ARMv8
  # `aese` and `pmull`, x86-64 AES-NI and `pclmulqdq`), both run on those
  # instructions, eight blocks at a time
  # (`GaloisCounterModeWithProcessorInstructions`). Elsewhere AES runs as a
  # Boolean circuit and GHASH as carry-less multiplies built from integer
  # ones, with no table (`BitslicedAdvancedEncryptionStandard` and
  # `GaloisHash`). Either way the running time is the same for every key and
  # every message.
  class AdvancedEncryptionStandardInGaloisCounterMode < AuthenticatedEncryption
    # The nonce size SP 800-38D recommends, in bytes.
    NONCE_BYTESIZE = 12

    # The tag sizes SP 800-38D §5.2.1.2 defines, in bytes. Sizes under 12
    # exist for formats that already use them; a short tag is easy to forge.
    LIST_OF_TAG_BYTESIZES = [16, 15, 14, 13, 12, 8, 4]

    @round_count : Int32

    # The portable code's round keys and hash key; empty when the processor's
    # instructions run.
    @round_keys : Slice(UInt64)
    @hash_key_state : Slice(UInt64)

    # The round keys as bytes and the hash key powers H to H^8, for the
    # processor's instructions; empty when the portable code runs.
    @round_key_bytes : Bytes
    @hash_key_powers : Bytes

    # Creates the cipher under *key* (16, 24 or 32 bytes). *tag_bytesize* is
    # the number of tag bytes kept on each message.
    def initialize(key : Bytes, *, tag_bytesize : Int32 = FULL_TAG_BYTESIZE)
      unless LIST_OF_TAG_BYTESIZES.includes?(tag_bytesize)
        raise TagSizeNotSupported.new("a GCM tag is #{LIST_OF_TAG_BYTESIZES.join(", ")} bytes, not #{tag_bytesize}")
      end
      @tag_bytesize = tag_bytesize
      @round_count = BitslicedAdvancedEncryptionStandard.round_count_for(key.size)
      if ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS
        @round_keys = Slice(UInt64).empty
        @hash_key_state = Slice(UInt64).empty
        @round_key_bytes = Bytes.new(BitslicedAdvancedEncryptionStandard::ROUND_KEY_BYTESIZE)
        @hash_key_powers = Bytes.new(GaloisCounterModeWithProcessorInstructions::HASH_KEY_POWERS_BYTESIZE)
        GaloisCounterModeWithProcessorInstructions.prepare(key, @round_key_bytes, @hash_key_powers)
        return
      end

      @round_key_bytes = Bytes.empty
      @hash_key_powers = Bytes.empty
      @round_keys = Slice(UInt64).new(BitslicedAdvancedEncryptionStandard::ROUND_KEY_WORD_COUNT, 0_u64)
      BitslicedAdvancedEncryptionStandard.expand_key(key, @round_keys)

      # The hash key is the encryption of the all-zero block.
      hash_key_storage = StaticArray(UInt8, 16).new(0_u8)
      hash_key = hash_key_storage.to_slice
      BitslicedAdvancedEncryptionStandard.encrypt_blocks(@round_keys, @round_count, hash_key, hash_key)
      @hash_key_state = Slice(UInt64).new(GaloisHash::STATE_WORD_COUNT, 0_u64)
      GaloisHash.load_key(@hash_key_state, hash_key)
      SecretWiping.wipe(hash_key)
    end

    def nonce_bytesize : Int32
      NONCE_BYTESIZE
    end

    protected def ensure_nonce_is_accepted(nonce : Bytes) : Nil
      raise NonceSizeMismatch.new("a GCM nonce holds at least one byte") if nonce.empty?
    end

    protected def apply_keystream(nonce : Bytes, input : Bytes, output : Bytes) : Nil
      counter_block_storage = uninitialized UInt8[16]
      counter_block = counter_block_storage.to_slice
      write_first_counter_block(nonce, counter_block)

      # The message starts one block after the block that masks the tag.
      counter = IO::ByteFormat::BigEndian.decode(UInt32, counter_block[12, 4])
      IO::ByteFormat::BigEndian.encode(counter &+ 1_u32, counter_block[12, 4])
      if ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS
        GaloisCounterModeWithProcessorInstructions.xor_counter_keystream(@round_key_bytes, @round_count, counter_block, input, output)
      else
        BitslicedAdvancedEncryptionStandard.xor_counter_keystream(@round_keys, @round_count, counter_block, input, output)
      end
      SecretWiping.wipe(counter_block)
    end

    # Encrypts and hashes the message in one pass where the processor's
    # instructions run.
    protected def seal(nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      return super unless ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS

      counter_block_storage = uninitialized UInt8[16]
      counter_block = counter_block_storage.to_slice
      write_first_counter_block(nonce, counter_block)
      GaloisCounterModeWithProcessorInstructions.seal(@round_key_bytes, @round_count, @hash_key_powers, counter_block,
        associated_data, plaintext, ciphertext, full_tag)
      SecretWiping.wipe(counter_block)
    end

    protected def compute_tag(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      counter_block_storage = uninitialized UInt8[16]
      counter_block = counter_block_storage.to_slice
      write_first_counter_block(nonce, counter_block)

      if ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS
        GaloisCounterModeWithProcessorInstructions.write_tag(@round_key_bytes, @round_count, @hash_key_powers, counter_block,
          associated_data, ciphertext, full_tag)
        SecretWiping.wipe(counter_block)
        return
      end

      hash_state_storage = uninitialized UInt64[8]
      hash_state = Slice.new(hash_state_storage.to_unsafe, GaloisHash::STATE_WORD_COUNT)
      hash_state.copy_from(@hash_key_state)
      GaloisHash.absorb(hash_state, associated_data)
      GaloisHash.absorb(hash_state, ciphertext)

      length_block_storage = uninitialized UInt8[16]
      length_block = length_block_storage.to_slice
      IO::ByteFormat::BigEndian.encode(associated_data.size.to_u64 * 8, length_block[0, 8])
      IO::ByteFormat::BigEndian.encode(ciphertext.size.to_u64 * 8, length_block[8, 8])
      GaloisHash.absorb(hash_state, length_block)

      digest_storage = uninitialized UInt8[16]
      digest = digest_storage.to_slice
      GaloisHash.write_digest(hash_state, digest)

      # The tag is the hash masked with the encryption of the first counter
      # block.
      BitslicedAdvancedEncryptionStandard.encrypt_blocks(@round_keys, @round_count, counter_block, counter_block)
      FULL_TAG_BYTESIZE.times { |index| full_tag.to_unsafe[index] = digest.to_unsafe[index] ^ counter_block.to_unsafe[index] }

      SecretWiping.wipe(digest)
      SecretWiping.wipe(counter_block)
      SecretWiping.wipe(Bytes.new(hash_state_storage.to_unsafe.as(UInt8*), 64))
    end

    # Writes the first counter block of SP 800-38D §7.1 step 2: a 12-byte
    # nonce followed by the number 1, or the hash of a nonce of another
    # length.
    private def write_first_counter_block(nonce : Bytes, counter_block : Bytes) : Nil
      if nonce.size == NONCE_BYTESIZE
        nonce.copy_to(counter_block[0, NONCE_BYTESIZE])
        counter_block[12] = 0_u8
        counter_block[13] = 0_u8
        counter_block[14] = 0_u8
        counter_block[15] = 1_u8
        return
      end

      length_block_storage = StaticArray(UInt8, 16).new(0_u8)
      length_block = length_block_storage.to_slice
      IO::ByteFormat::BigEndian.encode(nonce.size.to_u64 * 8, length_block[8, 8])

      if ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS
        accumulator_storage = StaticArray(UInt8, 16).new(0_u8)
        accumulator = accumulator_storage.to_slice
        GaloisCounterModeWithProcessorInstructions.absorb(accumulator, @hash_key_powers, nonce)
        GaloisCounterModeWithProcessorInstructions.absorb(accumulator, @hash_key_powers, length_block)
        GaloisCounterModeWithProcessorInstructions.write_digest(accumulator, counter_block)
        SecretWiping.wipe(accumulator)
        return
      end

      hash_state_storage = uninitialized UInt64[8]
      hash_state = Slice.new(hash_state_storage.to_unsafe, GaloisHash::STATE_WORD_COUNT)
      hash_state.copy_from(@hash_key_state)
      GaloisHash.absorb(hash_state, nonce)
      GaloisHash.absorb(hash_state, length_block)
      GaloisHash.write_digest(hash_state, counter_block)
      SecretWiping.wipe(Bytes.new(hash_state_storage.to_unsafe.as(UInt8*), 64))
    end
  end

  # The common name of `AdvancedEncryptionStandardInGaloisCounterMode`.
  alias AESGCM = AdvancedEncryptionStandardInGaloisCounterMode
end
