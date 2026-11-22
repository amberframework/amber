require "../declassification"
require "../error"
require "../secret_wiping"
require "../v1/bitsliced_advanced_encryption_standard"

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

    @round_keys : Slice(UInt64)
    @round_count : Int32

    # Creates the cipher under *key* (16, 24 or 32 bytes).
    def initialize(key : Bytes)
      @round_count = V1::BitslicedAdvancedEncryptionStandard.round_count_for(key.size)
      @round_keys = Slice(UInt64).new(V1::BitslicedAdvancedEncryptionStandard::ROUND_KEY_WORD_COUNT, 0_u64)
      V1::BitslicedAdvancedEncryptionStandard.expand_key(key, @round_keys)
    end

    # Returns *plaintext*, padded to a whole number of blocks, encrypted
    # under *initialization_vector* (16 bytes, fresh and unpredictable for
    # every message).
    def encrypt(plaintext : Bytes | String, *, initialization_vector : Bytes) : Bytes
      ensure_initialization_vector_fits(initialization_vector)
      plaintext_bytes = plaintext.to_slice
      padding_bytesize = BLOCK_BYTESIZE - plaintext_bytes.size % BLOCK_BYTESIZE
      ciphertext = Bytes.new(plaintext_bytes.size + padding_bytesize, padding_bytesize.to_u8)
      plaintext_bytes.copy_to(ciphertext)
      CipherBlockChaining.encrypt_in_place(@round_keys, @round_count, initialization_vector, ciphertext)
      ciphertext
    end

    # Returns the plaintext of *ciphertext*, or `nil` when the ciphertext is
    # empty, is not a whole number of blocks, or decrypts to malformed
    # padding. The padding is checked in constant time; whether it was well
    # formed, and how long it was, is what this method returns.
    def decrypt(ciphertext : Bytes, *, initialization_vector : Bytes) : Bytes?
      ensure_initialization_vector_fits(initialization_vector)
      return nil if ciphertext.empty? || ciphertext.size % BLOCK_BYTESIZE != 0

      padded_plaintext = Bytes.new(ciphertext.size)
      CipherBlockChaining.decrypt(@round_keys, @round_count, initialization_vector, ciphertext, padded_plaintext)
      last_block = padded_plaintext[padded_plaintext.size - BLOCK_BYTESIZE, BLOCK_BYTESIZE]
      padding_bytesize = Amber::Beryl::Crypto::Declassification.reveal(CipherBlockChaining.padding_bytesize(last_block))
      if padding_bytesize == 0
        Amber::Beryl::Crypto::SecretWiping.wipe(padded_plaintext)
        return nil
      end

      padded_plaintext[0, padded_plaintext.size - padding_bytesize]
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
