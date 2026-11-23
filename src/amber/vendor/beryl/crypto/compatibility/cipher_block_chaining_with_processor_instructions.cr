require "../armv8_cipher_instructions"
require "../error"
require "../secret_wiping"
require "../x86_64_cipher_instructions"
require "../v1/bitsliced_advanced_encryption_standard"

module Amber::Beryl::Crypto::Compatibility
  # :nodoc:
  #
  # AES-CBC on the processor's AES instructions: the assembly in
  # `Armv8CipherInstructions` or `X8664CipherInstructions`, with the round
  # keys stored as bytes in FIPS 197 order. Encryption runs one block after
  # another, since each block needs the ciphertext of the one before;
  # decryption runs eight blocks side by side, then the rest one at a time.
  #
  # Every buffer is treated as secret. Sizes are public.
  module CipherBlockChainingWithProcessorInstructions
    BLOCK_BYTESIZE = 16

    # Blocks one pass of the decryption loop takes side by side.
    private DECRYPTION_BLOCKS_PER_GROUP = 8

    ROUND_KEY_BYTESIZE = V1::BitslicedAdvancedEncryptionStandard::ROUND_KEY_BYTESIZE

    # Writes the encryption round keys of *key* into *round_key_bytes* and
    # those of the equivalent inverse cipher into
    # *decryption_round_key_bytes* (`ROUND_KEY_BYTESIZE` bytes each), and
    # returns the round count.
    def self.prepare(key : Bytes, round_key_bytes : Bytes, decryption_round_key_bytes : Bytes) : Int32
      round_count = V1::BitslicedAdvancedEncryptionStandard.round_count_for(key.size)
      V1::BitslicedAdvancedEncryptionStandard.write_round_key_bytes(key, round_key_bytes)
      unless decryption_round_key_bytes.size == ROUND_KEY_BYTESIZE
        raise OutputSizeMismatch.new("the round keys take #{ROUND_KEY_BYTESIZE} bytes")
      end

      prepare_decryption_round_keys(round_key_bytes.to_unsafe, decryption_round_key_bytes.to_unsafe, round_count)
      round_count
    end

    # Encrypts *plaintext*, a whole number of blocks, into *ciphertext*
    # (which may be the same buffer), chaining from *initialization_vector*.
    def self.encrypt(round_key_bytes : Bytes, round_count : Int32, initialization_vector : Bytes, plaintext : Bytes, ciphertext : Bytes) : Nil
      ensure_round_keys_fit(round_key_bytes)
      raise OutputSizeMismatch.new("CBC writes as many bytes as it reads") unless plaintext.size == ciphertext.size
      return if plaintext.empty?

      chaining_block_storage = uninitialized UInt8[16]
      chaining_block = chaining_block_storage.to_slice
      initialization_vector.copy_to(chaining_block)
      block_count = (plaintext.size // BLOCK_BYTESIZE).to_u64
      encrypt_chained(round_key_bytes.to_unsafe, round_count, chaining_block.to_unsafe, plaintext.to_unsafe, ciphertext.to_unsafe, block_count)
      SecretWiping.wipe(chaining_block)
    end

    # Decrypts *ciphertext*, a whole number of blocks, into
    # *padded_plaintext*, chaining from *initialization_vector*.
    def self.decrypt(decryption_round_key_bytes : Bytes, round_count : Int32, initialization_vector : Bytes,
                     ciphertext : Bytes, padded_plaintext : Bytes) : Nil
      ensure_round_keys_fit(decryption_round_key_bytes)
      raise OutputSizeMismatch.new("CBC writes as many bytes as it reads") unless ciphertext.size == padded_plaintext.size
      return if ciphertext.empty?

      chaining_block_storage = uninitialized UInt8[16]
      chaining_block = chaining_block_storage.to_slice
      initialization_vector.copy_to(chaining_block)
      block_count = ciphertext.size // BLOCK_BYTESIZE
      group_count = block_count // DECRYPTION_BLOCKS_PER_GROUP
      keys = decryption_round_key_bytes.to_unsafe
      done_group_count = 0
      {% if flag?(:aarch64) %}
        if group_count >= 4
          # The first group chains from the initialization vector; the
          # pipelined loop then reads each previous ciphertext block from
          # the message itself.
          decrypt_groups(keys, round_count, chaining_block.to_unsafe, ciphertext.to_unsafe, padded_plaintext.to_unsafe, 1_u64)
          pair_count = (group_count - 2) // 2
          offset = DECRYPTION_BLOCKS_PER_GROUP * BLOCK_BYTESIZE
          decrypt_pipelined(keys, round_count, ciphertext.to_unsafe + offset, padded_plaintext.to_unsafe + offset, pair_count.to_u64)
          done_group_count = 2 + pair_count * 2
          ciphertext[done_group_count * DECRYPTION_BLOCKS_PER_GROUP * BLOCK_BYTESIZE - BLOCK_BYTESIZE, BLOCK_BYTESIZE].copy_to(chaining_block)
        end
      {% end %}
      if group_count > done_group_count
        offset = done_group_count * DECRYPTION_BLOCKS_PER_GROUP * BLOCK_BYTESIZE
        decrypt_groups(keys, round_count, chaining_block.to_unsafe, ciphertext.to_unsafe + offset, padded_plaintext.to_unsafe + offset,
          (group_count - done_group_count).to_u64)
      end
      single_count = block_count - group_count * DECRYPTION_BLOCKS_PER_GROUP
      if single_count > 0
        offset = group_count * DECRYPTION_BLOCKS_PER_GROUP * BLOCK_BYTESIZE
        decrypt_singles(keys, round_count, chaining_block.to_unsafe, ciphertext.to_unsafe + offset, padded_plaintext.to_unsafe + offset, single_count.to_u64)
      end
      SecretWiping.wipe(chaining_block)
    end

    private def self.ensure_round_keys_fit(round_key_bytes : Bytes) : Nil
      return if round_key_bytes.size == ROUND_KEY_BYTESIZE

      raise OutputSizeMismatch.new("the round keys take #{ROUND_KEY_BYTESIZE} bytes")
    end

    # The assembly, kept out of line so that the program holds one copy of
    # each loop per round count. Callers pass a count of at least 1.
    @[NoInline]
    private def self.prepare_decryption_round_keys(round_keys : Pointer(UInt8), decryption_round_keys : Pointer(UInt8), round_count : Int32) : Nil
      {% for count in [10, 12, 14] %}
        if round_count == {{ count }}
          {% if flag?(:aarch64) %}
            Armv8CipherInstructions.prepare_decryption_round_keys(round_keys, decryption_round_keys, {{ count }})
          {% elsif flag?(:x86_64) %}
            X8664CipherInstructions.prepare_decryption_round_keys(round_keys, decryption_round_keys, {{ count }})
          {% else %}
            raise UnsupportedProcessor.new("this processor has no AES instructions Beryl can use")
          {% end %}
          return
        end
      {% end %}
      raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds, not #{round_count}")
    end

    @[NoInline]
    private def self.encrypt_chained(round_keys : Pointer(UInt8), round_count : Int32, chaining_block : Pointer(UInt8),
                                     input : Pointer(UInt8), output : Pointer(UInt8), block_count : UInt64) : Nil
      {% for count in [10, 12, 14] %}
        if round_count == {{ count }}
          {% if flag?(:aarch64) %}
            Armv8CipherInstructions.encrypt_chained_blocks(round_keys, chaining_block, input, output, block_count, {{ count }})
          {% elsif flag?(:x86_64) %}
            X8664CipherInstructions.encrypt_chained_blocks(round_keys, chaining_block, input, output, block_count, {{ count }})
          {% else %}
            raise UnsupportedProcessor.new("this processor has no AES instructions Beryl can use")
          {% end %}
          return
        end
      {% end %}
      raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds, not #{round_count}")
    end

    {% for kind in [{"decrypt_groups", 8}, {"decrypt_singles", 1}] %}
      @[NoInline]
      private def self.{{ kind[0].id }}(decryption_round_keys : Pointer(UInt8), round_count : Int32, chaining_block : Pointer(UInt8),
                                        input : Pointer(UInt8), output : Pointer(UInt8), group_count : UInt64) : Nil
        {% for count in [10, 12, 14] %}
          if round_count == {{ count }}
            {% if flag?(:aarch64) %}
              Armv8CipherInstructions.decrypt_chained_blocks(decryption_round_keys, chaining_block, input, output, group_count,
                {{ count }}, {{ kind[1] }})
            {% elsif flag?(:x86_64) %}
              X8664CipherInstructions.decrypt_chained_blocks(decryption_round_keys, chaining_block, input, output, group_count,
                {{ count }}, {{ kind[1] }})
            {% else %}
              raise UnsupportedProcessor.new("this processor has no AES instructions Beryl can use")
            {% end %}
            return
          end
        {% end %}
        raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds, not #{round_count}")
      end
    {% end %}

    {% if flag?(:aarch64) %}
      @[NoInline]
      private def self.decrypt_pipelined(decryption_round_keys : Pointer(UInt8), round_count : Int32, input : Pointer(UInt8),
                                         output : Pointer(UInt8), pair_count : UInt64) : Nil
        {% for count in [10, 12, 14] %}
          if round_count == {{ count }}
            Armv8CipherInstructions.decrypt_chained_blocks_pipelined(decryption_round_keys, input, output, pair_count, {{ count }})
            return
          end
        {% end %}
        raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds, not #{round_count}")
      end
    {% end %}
  end
end
