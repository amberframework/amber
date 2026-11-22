require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # The AES block cipher (FIPS 197) computed without any table: four blocks
  # are spread over eight 64-bit words, one word per bit position of a byte,
  # and every step of a round is Boolean logic on those words. The S-box is
  # the 113-gate circuit of Boyar and Peralta. Nothing the key or the data
  # holds decides a branch or a memory address, so the running time and the
  # cache footprint are the same for every key and every block.
  #
  # The design is BearSSL's `aes_ct64` (Thomas Pornin, MIT license,
  # https://www.bearssl.org/constanttime.html), translated to Crystal.
  #
  # Every buffer handed to these methods is treated as secret. Sizes and the
  # round count are public.
  module BitslicedAdvancedEncryptionStandard
    BLOCK_BYTESIZE = 16

    # One pass of the circuit encrypts this many blocks.
    BLOCKS_PER_PASS = 4

    # Eight words per round key, fifteen round keys for a 256-bit key.
    ROUND_KEY_WORD_COUNT = 120

    private ROUND_CONSTANTS = StaticArray[0x01_u32, 0x02_u32, 0x04_u32, 0x08_u32, 0x10_u32, 0x20_u32, 0x40_u32, 0x80_u32, 0x1b_u32, 0x36_u32]

    # Returns the number of rounds FIPS 197 gives a key of *key_bytesize*
    # bytes: 10, 12 or 14.
    def self.round_count_for(key_bytesize : Int32) : Int32
      unless key_bytesize == 16 || key_bytesize == 24 || key_bytesize == 32
        raise KeySizeMismatch.new("an AES key is 16, 24 or 32 bytes, not #{key_bytesize}")
      end

      key_bytesize // 4 + 6
    end

    # Runs the key schedule of FIPS 197 §5.2 on *key* and writes the round
    # keys, already spread over the eight bit-position words, into
    # *round_keys* (`ROUND_KEY_WORD_COUNT` words).
    def self.expand_key(key : Bytes, round_keys : Slice(UInt64)) : Nil
      round_count = round_count_for(key.size)
      raise OutputSizeMismatch.new("the round keys take #{ROUND_KEY_WORD_COUNT} words") unless round_keys.size == ROUND_KEY_WORD_COUNT

      key_word_count = key.size // 4
      schedule_word_count = (round_count + 1) * 4
      schedule_storage = uninitialized UInt32[60]
      schedule = schedule_storage.to_unsafe
      key_word_count.times { |index| schedule[index] = load_word(key.to_unsafe + index * 4) }

      working_storage = uninitialized UInt64[8]
      working = working_storage.to_unsafe
      previous_word = schedule[key_word_count - 1]
      position_in_key = 0
      round_constant_index = 0
      index = key_word_count
      while index < schedule_word_count
        if position_in_key == 0
          previous_word = (previous_word << 24) | (previous_word >> 8)
          previous_word = substitute_word(previous_word, working) ^ ROUND_CONSTANTS.to_unsafe[round_constant_index]
        elsif key_word_count > 6 && position_in_key == 4
          previous_word = substitute_word(previous_word, working)
        end
        previous_word ^= schedule[index - key_word_count]
        schedule[index] = previous_word
        position_in_key += 1
        if position_in_key == key_word_count
          position_in_key = 0
          round_constant_index += 1
        end
        index += 1
      end

      # Each round key becomes eight words in which every block slot holds the
      # same key bit, ready to be XORed into four blocks at once.
      destination = round_keys.to_unsafe
      round_key_index = 0
      while round_key_index <= round_count
        interleave_in(working, 0, schedule + round_key_index * 4)
        working[1] = working[0]
        working[2] = working[0]
        working[3] = working[0]
        working[5] = working[4]
        working[6] = working[4]
        working[7] = working[4]
        orthogonalize(working)
        8.times { |bit| destination[round_key_index * 8 + bit] = working[bit] }
        round_key_index += 1
      end

      SecretWiping.wipe(Bytes.new(schedule.as(UInt8*), 240))
      SecretWiping.wipe(Bytes.new(working.as(UInt8*), 64))
    end

    # Encrypts *input*, a whole number of blocks, into *output*, each block
    # on its own (the cipher's forward direction).
    def self.encrypt_blocks(round_keys : Slice(UInt64), round_count : Int32, input : Bytes, output : Bytes) : Nil
      transform_blocks(round_keys, round_count, input, output) { |working, keys| encrypt_state(working, keys, round_count) }
    end

    # Decrypts *input*, a whole number of blocks, into *output*, each block
    # on its own (the cipher's inverse direction).
    def self.decrypt_blocks(round_keys : Slice(UInt64), round_count : Int32, input : Bytes, output : Bytes) : Nil
      transform_blocks(round_keys, round_count, input, output) { |working, keys| decrypt_state(working, keys, round_count) }
    end

    # XORs *input* into *output* with the keystream of counter mode
    # (SP 800-38A §6.5). *counter_block* is the first counter block; its last
    # four bytes count up as a big-endian number that wraps at 2^32, which is
    # the increment GCM uses. *counter_block* itself is left as it was.
    def self.xor_counter_keystream(round_keys : Slice(UInt64), round_count : Int32, counter_block : Bytes,
                                   input : Bytes, output : Bytes) : Nil
      raise OutputSizeMismatch.new("counter mode writes as many bytes as it reads") unless input.size == output.size
      raise OutputSizeMismatch.new("a counter block is #{BLOCK_BYTESIZE} bytes") unless counter_block.size == BLOCK_BYTESIZE
      ensure_round_keys_fit(round_keys, round_count)

      keys = round_keys.to_unsafe
      working_storage = uninitialized UInt64[8]
      working = working_storage.to_unsafe
      words_storage = uninitialized UInt32[16]
      words = words_storage.to_unsafe
      keystream_storage = uninitialized UInt8[64]
      keystream = keystream_storage.to_unsafe

      counter_bytes = counter_block.to_unsafe
      nonce_word_0 = load_word(counter_bytes)
      nonce_word_1 = load_word(counter_bytes + 4)
      nonce_word_2 = load_word(counter_bytes + 8)
      counter = load_word(counter_bytes + 12).byte_swap

      source = input.to_unsafe
      destination = output.to_unsafe
      bytes_left = input.size
      while bytes_left > 0
        BLOCKS_PER_PASS.times do |slot|
          words[slot * 4] = nonce_word_0
          words[slot * 4 + 1] = nonce_word_1
          words[slot * 4 + 2] = nonce_word_2
          words[slot * 4 + 3] = (counter &+ slot.to_u32!).byte_swap
        end
        counter &+= BLOCKS_PER_PASS.to_u32!

        BLOCKS_PER_PASS.times { |slot| interleave_in(working, slot, words + slot * 4) }
        orthogonalize(working)
        encrypt_state(working, keys, round_count)
        orthogonalize(working)
        BLOCKS_PER_PASS.times { |slot| interleave_out(words + slot * 4, working, slot) }
        16.times { |index| store_word(keystream + index * 4, words[index]) }

        bytes_taken = Math.min(bytes_left, 64)
        bytes_taken.times { |index| destination[index] = source[index] ^ keystream[index] }
        source += bytes_taken
        destination += bytes_taken
        bytes_left -= bytes_taken
      end

      SecretWiping.wipe(keystream_storage.to_slice)
      SecretWiping.wipe(Bytes.new(words.as(UInt8*), 64))
      SecretWiping.wipe(Bytes.new(working.as(UInt8*), 64))
    end

    private def self.ensure_round_keys_fit(round_keys : Slice(UInt64), round_count : Int32) : Nil
      unless (round_count == 10 || round_count == 12 || round_count == 14) && round_keys.size == ROUND_KEY_WORD_COUNT
        raise KeySizeMismatch.new("AES runs 10, 12 or 14 rounds on #{ROUND_KEY_WORD_COUNT} round key words")
      end
    end

    private def self.transform_blocks(round_keys : Slice(UInt64), round_count : Int32, input : Bytes, output : Bytes,
                                      & : Pointer(UInt64), Pointer(UInt64) -> Nil) : Nil
      raise OutputSizeMismatch.new("a block cipher writes as many bytes as it reads") unless input.size == output.size
      raise OutputSizeMismatch.new("AES works on whole blocks of #{BLOCK_BYTESIZE} bytes") unless input.size % BLOCK_BYTESIZE == 0
      ensure_round_keys_fit(round_keys, round_count)

      keys = round_keys.to_unsafe
      working_storage = uninitialized UInt64[8]
      working = working_storage.to_unsafe
      words_storage = uninitialized UInt32[16]
      words = words_storage.to_unsafe

      source = input.to_unsafe
      destination = output.to_unsafe
      blocks_left = input.size // BLOCK_BYTESIZE
      while blocks_left > 0
        blocks_taken = Math.min(blocks_left, BLOCKS_PER_PASS)
        16.times { |index| words[index] = 0_u32 }
        (blocks_taken * 4).times { |index| words[index] = load_word(source + index * 4) }

        BLOCKS_PER_PASS.times { |slot| interleave_in(working, slot, words + slot * 4) }
        orthogonalize(working)
        yield working, keys
        orthogonalize(working)
        BLOCKS_PER_PASS.times { |slot| interleave_out(words + slot * 4, working, slot) }

        (blocks_taken * 4).times { |index| store_word(destination + index * 4, words[index]) }
        source += blocks_taken * BLOCK_BYTESIZE
        destination += blocks_taken * BLOCK_BYTESIZE
        blocks_left -= blocks_taken
      end

      SecretWiping.wipe(Bytes.new(words.as(UInt8*), 64))
      SecretWiping.wipe(Bytes.new(working.as(UInt8*), 64))
    end

    @[AlwaysInline]
    private def self.load_word(bytes : Pointer(UInt8)) : UInt32
      bytes[0].to_u32! | (bytes[1].to_u32! << 8) | (bytes[2].to_u32! << 16) | (bytes[3].to_u32! << 24)
    end

    @[AlwaysInline]
    private def self.store_word(bytes : Pointer(UInt8), word : UInt32) : Nil
      bytes[0] = word.to_u8!
      bytes[1] = (word >> 8).to_u8!
      bytes[2] = (word >> 16).to_u8!
      bytes[3] = (word >> 24).to_u8!
    end

    # The S-box applied to the four bytes of one word, for the key schedule.
    private def self.substitute_word(word : UInt32, working : Pointer(UInt64)) : UInt32
      8.times { |bit| working[bit] = 0_u64 }
      working[0] = word.to_u64!
      orthogonalize(working)
      substitute_bytes(working)
      orthogonalize(working)
      working[0].to_u32!
    end

    # Spreads the four words of one block over slot *slot* of the working
    # state (words *slot* and *slot* + 4).
    @[AlwaysInline]
    private def self.interleave_in(working : Pointer(UInt64), slot : Int32, words : Pointer(UInt32)) : Nil
      x0 = words[0].to_u64!
      x1 = words[1].to_u64!
      x2 = words[2].to_u64!
      x3 = words[3].to_u64!
      x0 |= (x0 << 16)
      x1 |= (x1 << 16)
      x2 |= (x2 << 16)
      x3 |= (x3 << 16)
      x0 &= 0x0000ffff0000ffff_u64
      x1 &= 0x0000ffff0000ffff_u64
      x2 &= 0x0000ffff0000ffff_u64
      x3 &= 0x0000ffff0000ffff_u64
      x0 |= (x0 << 8)
      x1 |= (x1 << 8)
      x2 |= (x2 << 8)
      x3 |= (x3 << 8)
      x0 &= 0x00ff00ff00ff00ff_u64
      x1 &= 0x00ff00ff00ff00ff_u64
      x2 &= 0x00ff00ff00ff00ff_u64
      x3 &= 0x00ff00ff00ff00ff_u64
      working[slot] = x0 | (x2 << 8)
      working[slot + 4] = x1 | (x3 << 8)
    end

    # The inverse of `interleave_in`.
    @[AlwaysInline]
    private def self.interleave_out(words : Pointer(UInt32), working : Pointer(UInt64), slot : Int32) : Nil
      q0 = working[slot]
      q1 = working[slot + 4]
      x0 = q0 & 0x00ff00ff00ff00ff_u64
      x1 = q1 & 0x00ff00ff00ff00ff_u64
      x2 = (q0 >> 8) & 0x00ff00ff00ff00ff_u64
      x3 = (q1 >> 8) & 0x00ff00ff00ff00ff_u64
      x0 |= (x0 >> 8)
      x1 |= (x1 >> 8)
      x2 |= (x2 >> 8)
      x3 |= (x3 >> 8)
      x0 &= 0x0000ffff0000ffff_u64
      x1 &= 0x0000ffff0000ffff_u64
      x2 &= 0x0000ffff0000ffff_u64
      x3 &= 0x0000ffff0000ffff_u64
      words[0] = x0.to_u32! | (x0 >> 16).to_u32!
      words[1] = x1.to_u32! | (x1 >> 16).to_u32!
      words[2] = x2.to_u32! | (x2 >> 16).to_u32!
      words[3] = x3.to_u32! | (x3 >> 16).to_u32!
    end

    private macro swap_bits(low_mask, high_mask, shift, first, second)
      %a = working[{{ first }}]
      %b = working[{{ second }}]
      working[{{ first }}] = (%a & {{ low_mask }}) | ((%b & {{ low_mask }}) << {{ shift }})
      working[{{ second }}] = ((%a & {{ high_mask }}) >> {{ shift }}) | (%b & {{ high_mask }})
    end

    # Turns the working state from "one word per block slot" into "one word
    # per bit position" and back; the transformation is its own inverse.
    @[AlwaysInline]
    private def self.orthogonalize(working : Pointer(UInt64)) : Nil
      swap_bits(0x5555555555555555_u64, 0xaaaaaaaaaaaaaaaa_u64, 1, 0, 1)
      swap_bits(0x5555555555555555_u64, 0xaaaaaaaaaaaaaaaa_u64, 1, 2, 3)
      swap_bits(0x5555555555555555_u64, 0xaaaaaaaaaaaaaaaa_u64, 1, 4, 5)
      swap_bits(0x5555555555555555_u64, 0xaaaaaaaaaaaaaaaa_u64, 1, 6, 7)

      swap_bits(0x3333333333333333_u64, 0xcccccccccccccccc_u64, 2, 0, 2)
      swap_bits(0x3333333333333333_u64, 0xcccccccccccccccc_u64, 2, 1, 3)
      swap_bits(0x3333333333333333_u64, 0xcccccccccccccccc_u64, 2, 4, 6)
      swap_bits(0x3333333333333333_u64, 0xcccccccccccccccc_u64, 2, 5, 7)

      swap_bits(0x0f0f0f0f0f0f0f0f_u64, 0xf0f0f0f0f0f0f0f0_u64, 4, 0, 4)
      swap_bits(0x0f0f0f0f0f0f0f0f_u64, 0xf0f0f0f0f0f0f0f0_u64, 4, 1, 5)
      swap_bits(0x0f0f0f0f0f0f0f0f_u64, 0xf0f0f0f0f0f0f0f0_u64, 4, 2, 6)
      swap_bits(0x0f0f0f0f0f0f0f0f_u64, 0xf0f0f0f0f0f0f0f0_u64, 4, 3, 7)
    end

    @[AlwaysInline]
    private def self.add_round_key(working : Pointer(UInt64), round_key : Pointer(UInt64)) : Nil
      8.times { |bit| working[bit] ^= round_key[bit] }
    end

    private def self.encrypt_state(working : Pointer(UInt64), round_keys : Pointer(UInt64), round_count : Int32) : Nil
      add_round_key(working, round_keys)
      round = 1
      while round < round_count
        substitute_bytes(working)
        shift_rows(working)
        mix_columns(working)
        add_round_key(working, round_keys + round * 8)
        round += 1
      end
      substitute_bytes(working)
      shift_rows(working)
      add_round_key(working, round_keys + round_count * 8)
    end

    private def self.decrypt_state(working : Pointer(UInt64), round_keys : Pointer(UInt64), round_count : Int32) : Nil
      add_round_key(working, round_keys + round_count * 8)
      round = round_count - 1
      while round > 0
        inverse_shift_rows(working)
        inverse_substitute_bytes(working)
        add_round_key(working, round_keys + round * 8)
        inverse_mix_columns(working)
        round -= 1
      end
      inverse_shift_rows(working)
      inverse_substitute_bytes(working)
      add_round_key(working, round_keys)
    end

    @[AlwaysInline]
    private def self.shift_rows(working : Pointer(UInt64)) : Nil
      8.times do |bit|
        bit_plane = working[bit]
        working[bit] = (bit_plane & 0x000000000000ffff_u64) |
                       ((bit_plane & 0x00000000fff00000_u64) >> 4) |
                       ((bit_plane & 0x00000000000f0000_u64) << 12) |
                       ((bit_plane & 0x0000ff0000000000_u64) >> 8) |
                       ((bit_plane & 0x000000ff00000000_u64) << 8) |
                       ((bit_plane & 0xf000000000000000_u64) >> 12) |
                       ((bit_plane & 0x0fff000000000000_u64) << 4)
      end
    end

    @[AlwaysInline]
    private def self.inverse_shift_rows(working : Pointer(UInt64)) : Nil
      8.times do |bit|
        bit_plane = working[bit]
        working[bit] = (bit_plane & 0x000000000000ffff_u64) |
                       ((bit_plane & 0x000000000fff0000_u64) << 4) |
                       ((bit_plane & 0x00000000f0000000_u64) >> 12) |
                       ((bit_plane & 0x000000ff00000000_u64) << 8) |
                       ((bit_plane & 0x0000ff0000000000_u64) >> 8) |
                       ((bit_plane & 0x000f000000000000_u64) << 12) |
                       ((bit_plane & 0xfff0000000000000_u64) >> 4)
      end
    end

    @[AlwaysInline]
    private def self.mix_columns(working : Pointer(UInt64)) : Nil
      q0 = working[0]
      q1 = working[1]
      q2 = working[2]
      q3 = working[3]
      q4 = working[4]
      q5 = working[5]
      q6 = working[6]
      q7 = working[7]
      r0 = q0.rotate_right(16)
      r1 = q1.rotate_right(16)
      r2 = q2.rotate_right(16)
      r3 = q3.rotate_right(16)
      r4 = q4.rotate_right(16)
      r5 = q5.rotate_right(16)
      r6 = q6.rotate_right(16)
      r7 = q7.rotate_right(16)

      working[0] = q7 ^ r7 ^ r0 ^ (q0 ^ r0).rotate_right(32)
      working[1] = q0 ^ r0 ^ q7 ^ r7 ^ r1 ^ (q1 ^ r1).rotate_right(32)
      working[2] = q1 ^ r1 ^ r2 ^ (q2 ^ r2).rotate_right(32)
      working[3] = q2 ^ r2 ^ q7 ^ r7 ^ r3 ^ (q3 ^ r3).rotate_right(32)
      working[4] = q3 ^ r3 ^ q7 ^ r7 ^ r4 ^ (q4 ^ r4).rotate_right(32)
      working[5] = q4 ^ r4 ^ r5 ^ (q5 ^ r5).rotate_right(32)
      working[6] = q5 ^ r5 ^ r6 ^ (q6 ^ r6).rotate_right(32)
      working[7] = q6 ^ r6 ^ r7 ^ (q7 ^ r7).rotate_right(32)
    end

    @[AlwaysInline]
    private def self.inverse_mix_columns(working : Pointer(UInt64)) : Nil
      q0 = working[0]
      q1 = working[1]
      q2 = working[2]
      q3 = working[3]
      q4 = working[4]
      q5 = working[5]
      q6 = working[6]
      q7 = working[7]
      r0 = q0.rotate_right(16)
      r1 = q1.rotate_right(16)
      r2 = q2.rotate_right(16)
      r3 = q3.rotate_right(16)
      r4 = q4.rotate_right(16)
      r5 = q5.rotate_right(16)
      r6 = q6.rotate_right(16)
      r7 = q7.rotate_right(16)

      working[0] = q5 ^ q6 ^ q7 ^ r0 ^ r5 ^ r7 ^ (q0 ^ q5 ^ q6 ^ r0 ^ r5).rotate_right(32)
      working[1] = q0 ^ q5 ^ r0 ^ r1 ^ r5 ^ r6 ^ r7 ^ (q1 ^ q5 ^ q7 ^ r1 ^ r5 ^ r6).rotate_right(32)
      working[2] = q0 ^ q1 ^ q6 ^ r1 ^ r2 ^ r6 ^ r7 ^ (q0 ^ q2 ^ q6 ^ r2 ^ r6 ^ r7).rotate_right(32)
      working[3] = q0 ^ q1 ^ q2 ^ q5 ^ q6 ^ r0 ^ r2 ^ r3 ^ r5 ^ (q0 ^ q1 ^ q3 ^ q5 ^ q6 ^ q7 ^ r0 ^ r3 ^ r5 ^ r7).rotate_right(32)
      working[4] = q1 ^ q2 ^ q3 ^ q5 ^ r1 ^ r3 ^ r4 ^ r5 ^ r6 ^ r7 ^ (q1 ^ q2 ^ q4 ^ q5 ^ q7 ^ r1 ^ r4 ^ r5 ^ r6).rotate_right(32)
      working[5] = q2 ^ q3 ^ q4 ^ q6 ^ r2 ^ r4 ^ r5 ^ r6 ^ r7 ^ (q2 ^ q3 ^ q5 ^ q6 ^ r2 ^ r5 ^ r6 ^ r7).rotate_right(32)
      working[6] = q3 ^ q4 ^ q5 ^ q7 ^ r3 ^ r5 ^ r6 ^ r7 ^ (q3 ^ q4 ^ q6 ^ q7 ^ r3 ^ r6 ^ r7).rotate_right(32)
      working[7] = q4 ^ q5 ^ q6 ^ r4 ^ r6 ^ r7 ^ (q4 ^ q5 ^ q7 ^ r4 ^ r7).rotate_right(32)
    end

    # The linear layer that turns the forward S-box circuit into the inverse
    # one: applied before and after `substitute_bytes`.
    @[AlwaysInline]
    private def self.inverse_substitution_linear_layer(working : Pointer(UInt64)) : Nil
      q0 = ~working[0]
      q1 = ~working[1]
      q2 = working[2]
      q3 = working[3]
      q4 = working[4]
      q5 = ~working[5]
      q6 = ~working[6]
      q7 = working[7]
      working[7] = q1 ^ q4 ^ q6
      working[6] = q0 ^ q3 ^ q5
      working[5] = q7 ^ q2 ^ q4
      working[4] = q6 ^ q1 ^ q3
      working[3] = q5 ^ q0 ^ q2
      working[2] = q4 ^ q7 ^ q1
      working[1] = q3 ^ q6 ^ q0
      working[0] = q2 ^ q5 ^ q7
    end

    private def self.inverse_substitute_bytes(working : Pointer(UInt64)) : Nil
      inverse_substitution_linear_layer(working)
      substitute_bytes(working)
      inverse_substitution_linear_layer(working)
    end

    # The AES S-box on all 32 bytes of the working state at once, as the
    # circuit of Boyar and Peralta ("A new combinational logic minimization
    # technique with applications to cryptology",
    # https://eprint.iacr.org/2009/191). x0 is the high bit of each byte.
    private def self.substitute_bytes(working : Pointer(UInt64)) : Nil
      x0 = working[7]
      x1 = working[6]
      x2 = working[5]
      x3 = working[4]
      x4 = working[3]
      x5 = working[2]
      x6 = working[1]
      x7 = working[0]

      # Top linear transformation.
      y14 = x3 ^ x5
      y13 = x0 ^ x6
      y9 = x0 ^ x3
      y8 = x0 ^ x5
      t0 = x1 ^ x2
      y1 = t0 ^ x7
      y4 = y1 ^ x3
      y12 = y13 ^ y14
      y2 = y1 ^ x0
      y5 = y1 ^ x6
      y3 = y5 ^ y8
      t1 = x4 ^ y12
      y15 = t1 ^ x5
      y20 = t1 ^ x1
      y6 = y15 ^ x7
      y10 = y15 ^ t0
      y11 = y20 ^ y9
      y7 = x7 ^ y11
      y17 = y10 ^ y11
      y19 = y10 ^ y8
      y16 = t0 ^ y11
      y21 = y13 ^ y16
      y18 = x0 ^ y16

      # Non-linear section.
      t2 = y12 & y15
      t3 = y3 & y6
      t4 = t3 ^ t2
      t5 = y4 & x7
      t6 = t5 ^ t2
      t7 = y13 & y16
      t8 = y5 & y1
      t9 = t8 ^ t7
      t10 = y2 & y7
      t11 = t10 ^ t7
      t12 = y9 & y11
      t13 = y14 & y17
      t14 = t13 ^ t12
      t15 = y8 & y10
      t16 = t15 ^ t12
      t17 = t4 ^ t14
      t18 = t6 ^ t16
      t19 = t9 ^ t14
      t20 = t11 ^ t16
      t21 = t17 ^ y20
      t22 = t18 ^ y19
      t23 = t19 ^ y21
      t24 = t20 ^ y18

      t25 = t21 ^ t22
      t26 = t21 & t23
      t27 = t24 ^ t26
      t28 = t25 & t27
      t29 = t28 ^ t22
      t30 = t23 ^ t24
      t31 = t22 ^ t26
      t32 = t31 & t30
      t33 = t32 ^ t24
      t34 = t23 ^ t33
      t35 = t27 ^ t33
      t36 = t24 & t35
      t37 = t36 ^ t34
      t38 = t27 ^ t36
      t39 = t29 & t38
      t40 = t25 ^ t39

      t41 = t40 ^ t37
      t42 = t29 ^ t33
      t43 = t29 ^ t40
      t44 = t33 ^ t37
      t45 = t42 ^ t41
      z0 = t44 & y15
      z1 = t37 & y6
      z2 = t33 & x7
      z3 = t43 & y16
      z4 = t40 & y1
      z5 = t29 & y7
      z6 = t42 & y11
      z7 = t45 & y17
      z8 = t41 & y10
      z9 = t44 & y12
      z10 = t37 & y3
      z11 = t33 & y4
      z12 = t43 & y13
      z13 = t40 & y5
      z14 = t29 & y2
      z15 = t42 & y9
      z16 = t45 & y14
      z17 = t41 & y8

      # Bottom linear transformation.
      t46 = z15 ^ z16
      t47 = z10 ^ z11
      t48 = z5 ^ z13
      t49 = z9 ^ z10
      t50 = z2 ^ z12
      t51 = z2 ^ z5
      t52 = z7 ^ z8
      t53 = z0 ^ z3
      t54 = z6 ^ z7
      t55 = z16 ^ z17
      t56 = z12 ^ t48
      t57 = t50 ^ t53
      t58 = z4 ^ t46
      t59 = z3 ^ t54
      t60 = t46 ^ t57
      t61 = z14 ^ t57
      t62 = t52 ^ t58
      t63 = t49 ^ t58
      t64 = z4 ^ t59
      t65 = t61 ^ t62
      t66 = z1 ^ t63
      s0 = t59 ^ t63
      s6 = t56 ^ ~t62
      s7 = t48 ^ ~t60
      t67 = t64 ^ t65
      s3 = t53 ^ t66
      s4 = t51 ^ t66
      s5 = t47 ^ t65
      s1 = t64 ^ ~s3
      s2 = t55 ^ ~t67

      working[7] = s0
      working[6] = s1
      working[5] = s2
      working[4] = s3
      working[3] = s4
      working[2] = s5
      working[1] = s6
      working[0] = s7
    end
  end
end
