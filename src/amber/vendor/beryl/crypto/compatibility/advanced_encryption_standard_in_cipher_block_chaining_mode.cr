require "../declassification"
require "../data_independent_timing"
require "../error"
require "../secret_wiping"
require "../processor_features"
require "../v1/bitsliced_advanced_encryption_standard"
require "./cipher_block_chaining_with_processor_instructions"

module Amber::Beryl::Crypto::Compatibility
  # AES in cipher block chaining mode with PKCS#7 padding (FIPS 197,
  # NIST SP 800-38A §6.2, RFC 5652 §6.3), under a 16, 24 or 32-byte key.
  #
  # CBC keeps a message private and does nothing to prove it is whole:
  # anyone can alter the ciphertext, and a receiver that reports bad padding
  # helps an attacker read it. It is here to read and write formats that
  # already use it (Amber's version 1 cookies, Grant's version 1 encrypted
  # attributes), which authenticate the ciphertext with HMAC *before* they
  # decrypt. New designs use `Amber::Beryl::Crypto.encrypt`.
  #
  # ```
  # cipher = Amber::Beryl::Crypto::Compatibility::AESCBC.new(key)
  # ciphertext = cipher.encrypt("a private note", initialization_vector: initialization_vector)
  # cipher.decrypt(ciphertext, initialization_vector: initialization_vector) # => the note's bytes, or nil
  # ```
  class AdvancedEncryptionStandardInCipherBlockChainingMode
    BLOCK_BYTESIZE = 16

    # The bitsliced round keys, or the encryption and decryption round keys
    # as bytes for the processor's AES instructions; the set not in use is
    # empty.
    @round_keys : Slice(UInt64)
    @round_key_bytes : Bytes
    @decryption_round_key_bytes : Bytes
    @round_count : Int32

    # Creates the cipher under *key* (16, 24 or 32 bytes).
    def initialize(key : Bytes)
      @round_count = V1::BitslicedAdvancedEncryptionStandard.round_count_for(key.size)
      if ProcessorFeatures::HAS_AES_INSTRUCTIONS
        @round_keys = Slice(UInt64).empty
        @round_key_bytes = Bytes.new(CipherBlockChainingWithProcessorInstructions::ROUND_KEY_BYTESIZE)
        @decryption_round_key_bytes = Bytes.new(CipherBlockChainingWithProcessorInstructions::ROUND_KEY_BYTESIZE)
        Amber::Beryl::Crypto::DataIndependentTiming.run do
          CipherBlockChainingWithProcessorInstructions.prepare(key, @round_key_bytes, @decryption_round_key_bytes)
        end
      else
        @round_keys = Slice(UInt64).new(V1::BitslicedAdvancedEncryptionStandard::ROUND_KEY_WORD_COUNT, 0_u64)
        @round_key_bytes = Bytes.empty
        @decryption_round_key_bytes = Bytes.empty
        Amber::Beryl::Crypto::DataIndependentTiming.run { V1::BitslicedAdvancedEncryptionStandard.expand_key(key, @round_keys) }
      end
    end

    # Returns *plaintext*, padded to a whole number of blocks, encrypted
    # under *initialization_vector* (16 bytes, fresh and unpredictable for
    # every message).
    def encrypt(plaintext : Bytes | String, *, initialization_vector : Bytes) : Bytes
      plaintext_bytes = plaintext.to_slice
      ciphertext = Bytes.new(padded_bytesize(plaintext_bytes.size))
      encrypt(plaintext_bytes, into: ciphertext, initialization_vector: initialization_vector)
      ciphertext
    end

    # Encrypts *plaintext* into *ciphertext*, which must hold the padded
    # length: `padded_bytesize(plaintext.size)` bytes.
    def encrypt(plaintext : Bytes | String, *, into ciphertext : Bytes, initialization_vector : Bytes) : Nil
      ensure_initialization_vector_fits(initialization_vector)
      plaintext_bytes = plaintext.to_slice
      unless ciphertext.size == padded_bytesize(plaintext_bytes.size)
        raise Amber::Beryl::Crypto::OutputSizeMismatch.new(
          "the ciphertext is #{padded_bytesize(plaintext_bytes.size)} bytes, the buffer holds #{ciphertext.size}"
        )
      end

      Amber::Beryl::Crypto::DataIndependentTiming.run { encrypt_with_padding(plaintext_bytes, ciphertext, initialization_vector) }
    end

    private def encrypt_with_padding(plaintext_bytes : Bytes, ciphertext : Bytes, initialization_vector : Bytes) : Nil
      padding_bytesize = ciphertext.size - plaintext_bytes.size
      if ProcessorFeatures::HAS_AES_INSTRUCTIONS
        # The whole blocks go straight from the plaintext; the last block,
        # with its padding, is built in place and chained from the block
        # before it.
        whole_bytesize = ciphertext.size - BLOCK_BYTESIZE
        CipherBlockChainingWithProcessorInstructions.encrypt(@round_key_bytes, @round_count, initialization_vector,
          plaintext_bytes[0, whole_bytesize], ciphertext[0, whole_bytesize])
        last_block = ciphertext[whole_bytesize, BLOCK_BYTESIZE]
        plaintext_bytes[whole_bytesize..].copy_to(last_block)
        last_block[BLOCK_BYTESIZE - padding_bytesize, padding_bytesize].fill(padding_bytesize.to_u8)
        chaining_block = whole_bytesize == 0 ? initialization_vector : ciphertext[whole_bytesize - BLOCK_BYTESIZE, BLOCK_BYTESIZE]
        CipherBlockChainingWithProcessorInstructions.encrypt(@round_key_bytes, @round_count, chaining_block, last_block, last_block)
      else
        plaintext_bytes.copy_to(ciphertext)
        ciphertext[plaintext_bytes.size, padding_bytesize].fill(padding_bytesize.to_u8)
        CipherBlockChaining.encrypt_in_place(@round_keys, @round_count, initialization_vector, ciphertext)
      end
    end

    # The length of the ciphertext of a *plaintext_bytesize*-byte message:
    # padding takes it to the next whole block, adding a block when it is
    # whole already.
    def padded_bytesize(plaintext_bytesize : Int32) : Int32
      plaintext_bytesize + BLOCK_BYTESIZE - plaintext_bytesize % BLOCK_BYTESIZE
    end

    # Returns the plaintext of *ciphertext*, or `nil` when the ciphertext is
    # empty, is not a whole number of blocks, or decrypts to malformed
    # padding. The padding is checked in constant time; whether it was well
    # formed, and how long it was, is what this method returns.
    def decrypt(ciphertext : Bytes, *, initialization_vector : Bytes) : Bytes?
      ensure_initialization_vector_fits(initialization_vector)
      return nil if ciphertext.empty? || ciphertext.size % BLOCK_BYTESIZE != 0

      padded_plaintext = Bytes.new(ciphertext.size)
      plaintext_bytesize = decrypt(ciphertext, into: padded_plaintext, initialization_vector: initialization_vector)
      return nil unless plaintext_bytesize

      padded_plaintext[0, plaintext_bytesize]
    end

    # Decrypts *ciphertext* into *padded_plaintext*, which must be as long,
    # and returns how many of its first bytes are the plaintext; or returns
    # `nil`, with *padded_plaintext* wiped, when the ciphertext is empty, is
    # not a whole number of blocks, or decrypts to malformed padding.
    def decrypt(ciphertext : Bytes, *, into padded_plaintext : Bytes, initialization_vector : Bytes) : Int32?
      ensure_initialization_vector_fits(initialization_vector)
      return nil if ciphertext.empty? || ciphertext.size % BLOCK_BYTESIZE != 0
      unless padded_plaintext.size == ciphertext.size
        raise Amber::Beryl::Crypto::OutputSizeMismatch.new("the buffer holds #{padded_plaintext.size} bytes, the ciphertext #{ciphertext.size}")
      end

      padding_bytesize = Amber::Beryl::Crypto::Declassification.reveal(Amber::Beryl::Crypto::DataIndependentTiming.run do
        if ProcessorFeatures::HAS_AES_INSTRUCTIONS
          CipherBlockChainingWithProcessorInstructions.decrypt(@decryption_round_key_bytes, @round_count, initialization_vector,
            ciphertext, padded_plaintext)
        else
          CipherBlockChaining.decrypt(@round_keys, @round_count, initialization_vector, ciphertext, padded_plaintext)
        end
        CipherBlockChaining.padding_bytesize(padded_plaintext[padded_plaintext.size - BLOCK_BYTESIZE, BLOCK_BYTESIZE])
      end)
      if padding_bytesize == 0
        Amber::Beryl::Crypto::SecretWiping.wipe(padded_plaintext)
        return nil
      end

      padded_plaintext.size - padding_bytesize.to_i32
    end

    private def ensure_initialization_vector_fits(initialization_vector : Bytes) : Nil
      return if initialization_vector.size == BLOCK_BYTESIZE

      raise Amber::Beryl::Crypto::NonceSizeMismatch.new(
        "a CBC initialization vector is #{BLOCK_BYTESIZE} bytes, not #{initialization_vector.size}"
      )
    end
  end

  # The common name of `AdvancedEncryptionStandardInCipherBlockChainingMode`.
  alias AESCBC = AdvancedEncryptionStandardInCipherBlockChainingMode

  # :nodoc:
  #
  # The chaining of SP 800-38A §6.2 and the padding check of RFC 5652 §6.3.
  # Every buffer is treated as secret; sizes are public.
  module CipherBlockChaining
    BLOCK_BYTESIZE = 16

    # Encrypts *buffer*, a whole number of blocks, where it lies: each block
    # is XORed with the ciphertext block before it (the initialization
    # vector for the first) and then encrypted.
    def self.encrypt_in_place(round_keys : Slice(UInt64), round_count : Int32, initialization_vector : Bytes, buffer : Bytes) : Nil
      previous_block = initialization_vector.to_unsafe
      offset = 0
      while offset < buffer.size
        block = buffer[offset, BLOCK_BYTESIZE]
        BLOCK_BYTESIZE.times { |index| block.to_unsafe[index] ^= previous_block[index] }
        V1::BitslicedAdvancedEncryptionStandard.encrypt_blocks(round_keys, round_count, block, block)
        previous_block = block.to_unsafe
        offset += BLOCK_BYTESIZE
      end
    end

    # Decrypts *ciphertext*, a whole number of blocks, into
    # *padded_plaintext*: every block is decrypted, then XORed with the
    # ciphertext block before it.
    def self.decrypt(round_keys : Slice(UInt64), round_count : Int32, initialization_vector : Bytes,
                     ciphertext : Bytes, padded_plaintext : Bytes) : Nil
      V1::BitslicedAdvancedEncryptionStandard.decrypt_blocks(round_keys, round_count, ciphertext, padded_plaintext)
      destination = padded_plaintext.to_unsafe
      BLOCK_BYTESIZE.times { |index| destination[index] ^= initialization_vector.to_unsafe[index] }
      index = BLOCK_BYTESIZE
      while index < ciphertext.size
        destination[index] ^= ciphertext.to_unsafe[index - BLOCK_BYTESIZE]
        index += 1
      end
    end

    # Returns the number of PKCS#7 padding bytes at the end of *last_block*
    # (1 to 16), or 0 when the padding is malformed. Every byte of the block
    # is read and compared whatever the block holds.
    def self.padding_bytesize(last_block : Bytes) : UInt32
      raise Amber::Beryl::Crypto::OutputSizeMismatch.new("the padding check reads one block of #{BLOCK_BYTESIZE} bytes") unless last_block.size == BLOCK_BYTESIZE

      bytes = last_block.to_unsafe
      padding_bytesize = bytes[BLOCK_BYTESIZE - 1].to_u32!
      difference = 0_u32
      BLOCK_BYTESIZE.times do |distance_from_end|
        # All ones when this byte lies inside the padding.
        is_inside_padding = 0_u32 &- ((distance_from_end.to_u32! &- padding_bytesize) >> 31)
        difference |= is_inside_padding & (bytes[BLOCK_BYTESIZE - 1 - distance_from_end].to_u32! ^ padding_bytesize)
      end
      # A padding size of 0, or over one block, is malformed.
      difference |= (padding_bytesize &- 1_u32) >> 31
      difference |= (BLOCK_BYTESIZE.to_u32! &- padding_bytesize) >> 31

      is_well_formed = ((difference | (0_u32 &- difference)) >> 31) &- 1_u32
      padding_bytesize & is_well_formed
    end
  end
end
