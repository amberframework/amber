require "../error"
require "../processor_features"
require "../secret_wiping"
require "../armv8_cipher_instructions"
require "../x86_64_cipher_instructions"
require "./bitsliced_advanced_encryption_standard"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # AES-GCM on the processor's AES and carry-less multiply instructions
  # (`ProcessorFeatures::HAS_GALOIS_COUNTER_MODE_INSTRUCTIONS`):
  # `Armv8CipherInstructions` on AArch64, `X8664CipherInstructions` on
  # x86-64. The assembly works on whole blocks, sixteen at a time where
  # there are sixteen, so that the processor keeps many blocks in flight;
  # this module cuts a message into those groups and handles its last
  # partial block.
  #
  # Sealing runs counter mode and then GHASH over each 16 KiB of the
  # message, so the ciphertext is hashed while it is still in the
  # processor's first-level cache. A short message, with its associated data
  # and its lengths block, is hashed with a single reduction, and its counter
  # blocks, the one that masks the tag included, are encrypted in one call.
  #
  # Every buffer handed to these methods is treated as secret. Sizes and the
  # round count are public.
  module GaloisCounterModeWithProcessorInstructions
    BLOCK_BYTESIZE = 16

    # The blocks one pass of the wide loops works on, and the number of hash
    # key powers kept.
    BLOCKS_PER_GROUP = 16

    # The bytes of one group of blocks.
    GROUP_BYTESIZE = BLOCK_BYTESIZE * BLOCKS_PER_GROUP

    # The blocks in one group of the counter-mode loop, which keeps two such
    # groups in flight.
    COUNTER_BLOCKS_PER_GROUP = 8

    # The bytes of one table entry of hash key powers.
    HASH_KEY_POWER_BYTESIZE = 32

    # The bytes of the table of hash key powers, H^16 down to H.
    HASH_KEY_POWERS_BYTESIZE = HASH_KEY_POWER_BYTESIZE * BLOCKS_PER_GROUP

    # The bytes of the GHASH accumulator.
    ACCUMULATOR_BYTESIZE = 16

    # Sealing encrypts and hashes this much of a long message at a time.
    SEALING_CHUNK_BYTESIZE = 16 * 1024

    # Writes the round keys of *key* into *round_keys* and the table of hash
    # key powers into *hash_key_powers*.
    def self.prepare(key : Bytes, round_keys : Bytes, hash_key_powers : Bytes) : Nil
      raise OutputSizeMismatch.new("the hash key powers take #{HASH_KEY_POWERS_BYTESIZE} bytes") unless hash_key_powers.size == HASH_KEY_POWERS_BYTESIZE

      BitslicedAdvancedEncryptionStandard.write_round_key_bytes(key, round_keys)
      round_count = BitslicedAdvancedEncryptionStandard.round_count_for(key.size)

      # The hash key is the encryption of the all-zero block, which is the
      # keystream of the all-zero counter block.
      hash_key_storage = StaticArray(UInt8, 16).new(0_u8)
      hash_key = hash_key_storage.to_slice
      counter_block_storage = StaticArray(UInt8, 16).new(0_u8)
      encrypt_counter_blocks(round_keys, round_count, counter_block_storage.to_slice, hash_key, hash_key)
      prepare_hash_key_powers(hash_key, hash_key_powers)
      SecretWiping.wipe(hash_key)
    end

    # Encrypts *plaintext* into *ciphertext* and writes the full tag of the
    # ciphertext and *associated_data* into *full_tag*. *counter_block* is
    # the first counter block (J0); it is left holding the next unused one.
    def self.seal(round_keys : Bytes, round_count : Int32, hash_key_powers : Bytes, counter_block : Bytes,
                  associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      raise OutputSizeMismatch.new("counter mode writes as many bytes as it reads") unless plaintext.size == ciphertext.size

      accumulator_storage = StaticArray(UInt8, 16).new(0_u8)
      accumulator = accumulator_storage.to_slice
      tag_mask_storage = StaticArray(UInt8, 16).new(0_u8)
      tag_mask = tag_mask_storage.to_slice

      if plaintext.size < GROUP_BYTESIZE - BLOCK_BYTESIZE
        # A short message: its counter blocks follow the tag mask's, so one
        # call encrypts them all, and one hash covers the whole message.
        encrypt_after_tag_mask(round_keys, round_count, counter_block, plaintext, ciphertext, tag_mask)
        absorb_closing_blocks(accumulator, hash_key_powers, associated_data, ciphertext, associated_data.size, ciphertext.size)
      else
        encrypt_counter_blocks(round_keys, round_count, counter_block, tag_mask, tag_mask)
        absorb(accumulator, hash_key_powers, associated_data)
        offset = 0
        while plaintext.size - offset > SEALING_CHUNK_BYTESIZE
          chunk_ciphertext = ciphertext[offset, SEALING_CHUNK_BYTESIZE]
          encrypt_counter_blocks(round_keys, round_count, counter_block, plaintext[offset, SEALING_CHUNK_BYTESIZE], chunk_ciphertext)
          absorb_whole_blocks(accumulator, hash_key_powers, chunk_ciphertext)
          offset += SEALING_CHUNK_BYTESIZE
        end
        last_ciphertext = ciphertext[offset, plaintext.size - offset]
        xor_counter_keystream(round_keys, round_count, counter_block, plaintext[offset, plaintext.size - offset], last_ciphertext)
        last_whole_bytesize = last_ciphertext.size - last_ciphertext.size % GROUP_BYTESIZE
        absorb_whole_blocks(accumulator, hash_key_powers, last_ciphertext[0, last_whole_bytesize])
        absorb_closing_blocks(accumulator, hash_key_powers, Bytes.empty, last_ciphertext[last_whole_bytesize, last_ciphertext.size - last_whole_bytesize],
          associated_data.size, ciphertext.size)
      end
      write_masked_digest(accumulator, tag_mask, full_tag)

      SecretWiping.wipe(tag_mask)
      SecretWiping.wipe(accumulator)
    end

    # Writes into *full_tag* the full tag of *ciphertext* and
    # *associated_data*. *counter_block* is the first counter block (J0); it
    # is left holding the next one, where the message's keystream starts.
    def self.write_tag(round_keys : Bytes, round_count : Int32, hash_key_powers : Bytes, counter_block : Bytes,
                       associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      accumulator_storage = StaticArray(UInt8, 16).new(0_u8)
      accumulator = accumulator_storage.to_slice
      tag_mask_storage = StaticArray(UInt8, 16).new(0_u8)
      tag_mask = tag_mask_storage.to_slice
      encrypt_counter_blocks(round_keys, round_count, counter_block, tag_mask, tag_mask)

      grouped_bytesize = ciphertext.size - ciphertext.size % GROUP_BYTESIZE
      if grouped_bytesize == 0
        absorb_closing_blocks(accumulator, hash_key_powers, associated_data, ciphertext, associated_data.size, ciphertext.size)
      else
        absorb(accumulator, hash_key_powers, associated_data)
        absorb_whole_blocks(accumulator, hash_key_powers, ciphertext[0, grouped_bytesize])
        absorb_closing_blocks(accumulator, hash_key_powers, Bytes.empty, ciphertext[grouped_bytesize, ciphertext.size - grouped_bytesize],
          associated_data.size, ciphertext.size)
      end
      write_masked_digest(accumulator, tag_mask, full_tag)

      SecretWiping.wipe(tag_mask)
      SecretWiping.wipe(accumulator)
    end

    # XORs the counter-mode keystream that starts at *counter_block* into
    # *input* and writes it to *output*; a last block that is not full takes
    # the first bytes of its keystream block. *counter_block* is left
    # holding the next counter block.
    def self.xor_counter_keystream(round_keys : Bytes, round_count : Int32, counter_block : Bytes, input : Bytes, output : Bytes) : Nil
      raise OutputSizeMismatch.new("counter mode writes as many bytes as it reads") unless input.size == output.size

      whole_bytesize = input.size - input.size % BLOCK_BYTESIZE
      encrypt_counter_blocks(round_keys, round_count, counter_block, input[0, whole_bytesize], output[0, whole_bytesize])
      return if whole_bytesize == input.size

      partial_block_storage = StaticArray(UInt8, 16).new(0_u8)
      partial_block = partial_block_storage.to_slice
      tail_bytesize = input.size - whole_bytesize
      input[whole_bytesize, tail_bytesize].copy_to(partial_block)
      encrypt_counter_blocks(round_keys, round_count, counter_block, partial_block, partial_block)
      partial_block[0, tail_bytesize].copy_to(output[whole_bytesize, tail_bytesize])
      SecretWiping.wipe(partial_block)
    end

    # Mixes *message* into the GHASH *accumulator*; a last block that is
    # not full is padded with zeros.
    def self.absorb(accumulator : Bytes, hash_key_powers : Bytes, message : Bytes) : Nil
      whole_bytesize = message.size - message.size % BLOCK_BYTESIZE
      absorb_whole_blocks(accumulator, hash_key_powers, message[0, whole_bytesize])
      return if whole_bytesize == message.size

      partial_block_storage = StaticArray(UInt8, 16).new(0_u8)
      partial_block = partial_block_storage.to_slice
      message[whole_bytesize, message.size - whole_bytesize].copy_to(partial_block)
      absorb_whole_blocks(accumulator, hash_key_powers, partial_block)
      SecretWiping.wipe(partial_block)
    end

    # Writes into *digest* (16 bytes) the GHASH value the *accumulator*
    # holds, in the order of the standard's bytes.
    def self.write_digest(accumulator : Bytes, digest : Bytes) : Nil
      raise OutputSizeMismatch.new("a GHASH digest is #{BLOCK_BYTESIZE} bytes, the buffer holds #{digest.size}") unless digest.size == BLOCK_BYTESIZE

      BLOCK_BYTESIZE.times { |index| digest.to_unsafe[index] = accumulator.to_unsafe[BLOCK_BYTESIZE - 1 - index] }
    end

    # Writes into *full_tag* the digest of the *accumulator* XORed with
    # *tag_mask*.
    private def self.write_masked_digest(accumulator : Bytes, tag_mask : Bytes, full_tag : Bytes) : Nil
      write_digest(accumulator, full_tag)
      BLOCK_BYTESIZE.times { |index| full_tag.to_unsafe[index] ^= tag_mask.to_unsafe[index] }
    end

    # Encrypts the counter block at *counter_block* into *tag_mask* and
    # *plaintext* (shorter than 15 blocks) into *ciphertext* with the counter
    # blocks after it, in one call.
    private def self.encrypt_after_tag_mask(round_keys : Bytes, round_count : Int32, counter_block : Bytes,
                                            plaintext : Bytes, ciphertext : Bytes, tag_mask : Bytes) : Nil
      staging_storage = StaticArray(UInt8, 256).new(0_u8)
      padded_bytesize = (plaintext.size + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE * BLOCK_BYTESIZE
      staging = staging_storage.to_slice[0, BLOCK_BYTESIZE + padded_bytesize]
      plaintext.copy_to(staging[BLOCK_BYTESIZE, plaintext.size])
      encrypt_counter_blocks(round_keys, round_count, counter_block, staging, staging)
      staging[0, BLOCK_BYTESIZE].copy_to(tag_mask)
      staging[BLOCK_BYTESIZE, plaintext.size].copy_to(ciphertext)
      SecretWiping.wipe(staging_storage.to_slice)
    end

    # Mixes *leading* and then *trailing*, each padded with zeros to whole
    # blocks, and then the lengths block of SP 800-38D §7.1 step 5 into the
    # *accumulator*. When they fit in one group they are laid out side by
    # side and reduced once.
    private def self.absorb_closing_blocks(accumulator : Bytes, hash_key_powers : Bytes, leading : Bytes, trailing : Bytes,
                                           associated_data_bytesize : Int32, ciphertext_bytesize : Int32) : Nil
      leading_padded_bytesize = (leading.size + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE * BLOCK_BYTESIZE
      trailing_padded_bytesize = (trailing.size + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE * BLOCK_BYTESIZE
      staging_storage = StaticArray(UInt8, 256).new(0_u8)
      staging = staging_storage.to_slice
      if leading_padded_bytesize + trailing_padded_bytesize + BLOCK_BYTESIZE <= GROUP_BYTESIZE
        leading.copy_to(staging[0, leading.size])
        trailing.copy_to(staging[leading_padded_bytesize, trailing.size])
        length_offset = leading_padded_bytesize + trailing_padded_bytesize
      else
        absorb(accumulator, hash_key_powers, leading)
        absorb(accumulator, hash_key_powers, trailing)
        length_offset = 0
      end
      IO::ByteFormat::BigEndian.encode(associated_data_bytesize.to_u64 * 8, staging[length_offset, 8])
      IO::ByteFormat::BigEndian.encode(ciphertext_bytesize.to_u64 * 8, staging[length_offset + 8, 8])
      absorb_whole_blocks(accumulator, hash_key_powers, staging[0, length_offset + BLOCK_BYTESIZE])
      SecretWiping.wipe(staging)
    end

    # Encrypts the whole blocks of *input* into *output* in counter mode:
    # an odd number of groups of eight in the software-pipelined loop, then
    # the blocks left over one at a time.
    private def self.encrypt_counter_blocks(round_keys : Bytes, round_count : Int32, counter_block : Bytes, input : Bytes, output : Bytes) : Nil
      raise OutputSizeMismatch.new("counter mode writes as many bytes as it reads") unless input.size == output.size

      block_count = input.size // BLOCK_BYTESIZE
      group_count = block_count // COUNTER_BLOCKS_PER_GROUP
      pipelined_block_count = 0
      if group_count >= 3
        pair_count = ((group_count - 1) // 2).to_u64
        encrypt_counter_groups(round_keys, round_count, counter_block, input.to_unsafe, output.to_unsafe, pair_count)
        pipelined_block_count = (pair_count.to_i32 * 2 + 1) * COUNTER_BLOCKS_PER_GROUP
      end
      single_count = (block_count - pipelined_block_count).to_u64
      return if single_count == 0

      offset = pipelined_block_count * BLOCK_BYTESIZE
      encrypt_counter_singles(round_keys, round_count, counter_block, input.to_unsafe + offset, output.to_unsafe + offset, single_count)
    end

    # Mixes the whole blocks of *blocks_to_absorb* into the accumulator:
    # each group of sixteen multiplied by H^16 to H and reduced once, then
    # the blocks left over, n of them, multiplied by the powers from H^n down
    # and reduced once.
    private def self.absorb_whole_blocks(accumulator : Bytes, hash_key_powers : Bytes, blocks_to_absorb : Bytes) : Nil
      raise OutputSizeMismatch.new("the GHASH accumulator is #{ACCUMULATOR_BYTESIZE} bytes") unless accumulator.size == ACCUMULATOR_BYTESIZE
      raise OutputSizeMismatch.new("the hash key powers take #{HASH_KEY_POWERS_BYTESIZE} bytes") unless hash_key_powers.size == HASH_KEY_POWERS_BYTESIZE

      block_count = blocks_to_absorb.size // BLOCK_BYTESIZE
      group_count = (block_count // BLOCKS_PER_GROUP).to_u64
      absorb_groups(accumulator, hash_key_powers.to_unsafe, blocks_to_absorb.to_unsafe, group_count) if group_count > 0
      single_count = block_count % BLOCKS_PER_GROUP
      return if single_count == 0

      first_power_offset = (BLOCKS_PER_GROUP - single_count) * HASH_KEY_POWER_BYTESIZE
      absorb_with_one_reduction(accumulator, hash_key_powers.to_unsafe + first_power_offset,
        blocks_to_absorb.to_unsafe + group_count * GROUP_BYTESIZE, single_count.to_u64)
    end

    # Each method below holds the assembly for one kind of loop, once per
    # round count (and, on AArch64, with and without `eor3`), and is kept
    # out of line so that the program holds one copy of it. Callers pass a
    # count of at least 1.
    {% for kind in [{"encrypt_counter_groups", true}, {"encrypt_counter_singles", false}] %}
      @[NoInline]
      private def self.{{ kind[0].id }}(round_keys : Bytes, round_count : Int32, counter_block : Bytes,
                                        input : Pointer(UInt8), output : Pointer(UInt8), group_count : UInt64) : Nil
        raise OutputSizeMismatch.new("the round keys take #{BitslicedAdvancedEncryptionStandard::ROUND_KEY_BYTESIZE} bytes") unless round_keys.size == BitslicedAdvancedEncryptionStandard::ROUND_KEY_BYTESIZE
        raise OutputSizeMismatch.new("a counter block is #{BLOCK_BYTESIZE} bytes") unless counter_block.size == BLOCK_BYTESIZE

        round_keys_pointer = round_keys.to_unsafe
        counter_block_pointer = counter_block.to_unsafe
        {% for has_three_way_exclusive_or in [true, false] %}
          if ProcessorFeatures::HAS_THREE_WAY_EXCLUSIVE_OR == {{ has_three_way_exclusive_or }}
            {% for round_count in [10, 12, 14] %}
              if round_count == {{ round_count }}
                {% if flag?(:aarch64) %}
                  Armv8CipherInstructions.encrypt_counter_blocks(round_keys_pointer, counter_block_pointer, input, output, group_count,
                    {{ round_count }}, {{ kind[1] }}, {{ has_three_way_exclusive_or }})
                {% elsif flag?(:x86_64) %}
                  X8664CipherInstructions.encrypt_counter_blocks(round_keys_pointer, counter_block_pointer, input, output, group_count,
                    {{ round_count }}, {{ kind[1] }})
                {% else %}
                  raise UnsupportedProcessor.new("this processor has no AES instructions Beryl can use")
                {% end %}
                return
              end
            {% end %}
          end
        {% end %}
        raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds, not #{round_count}")
      end
    {% end %}

    # *first_hash_key_power* points at the table entry of the power the
    # first block is multiplied by.
    {% for kind in [{"absorb_groups", 16}, {"absorb_with_one_reduction", 1}] %}
      @[NoInline]
      private def self.{{ kind[0].id }}(accumulator : Bytes, first_hash_key_power : Pointer(UInt8), input : Pointer(UInt8), group_count : UInt64) : Nil
        accumulator_pointer = accumulator.to_unsafe
        {% if flag?(:aarch64) %}
          if ProcessorFeatures::HAS_THREE_WAY_EXCLUSIVE_OR
            Armv8CipherInstructions.absorb_hash_blocks(accumulator_pointer, first_hash_key_power, input, group_count, {{ kind[1] }}, true)
          else
            Armv8CipherInstructions.absorb_hash_blocks(accumulator_pointer, first_hash_key_power, input, group_count, {{ kind[1] }}, false)
          end
        {% elsif flag?(:x86_64) %}
          X8664CipherInstructions.absorb_hash_blocks(accumulator_pointer, first_hash_key_power, input, group_count, {{ kind[1] }})
        {% else %}
          raise UnsupportedProcessor.new("this processor has no carry-less multiply Beryl can use")
        {% end %}
      end
    {% end %}

    @[NoInline]
    private def self.prepare_hash_key_powers(hash_key : Bytes, hash_key_powers : Bytes) : Nil
      hash_key_pointer = hash_key.to_unsafe
      hash_key_powers_pointer = hash_key_powers.to_unsafe
      {% if flag?(:aarch64) %}
        Armv8CipherInstructions.prepare_hash_key_powers(hash_key_pointer, hash_key_powers_pointer)
      {% elsif flag?(:x86_64) %}
        X8664CipherInstructions.prepare_hash_key_powers(hash_key_pointer, hash_key_powers_pointer)
      {% else %}
        raise UnsupportedProcessor.new("this processor has no carry-less multiply Beryl can use")
      {% end %}
    end
  end
end
