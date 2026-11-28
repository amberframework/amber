require "../error"
require "../processor_features"
require "../secret_wiping"
require "../x86_64_cipher_instructions"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Poly1305 (RFC 8439 §2.5) for the encrypted messages of ChaCha20-Poly1305,
  # on 64-bit processors, whose multiply instructions give the whole 128-bit
  # product of two 64-bit words (`mul` and `umulh` on AArch64, `mul` on
  # x86-64). The accumulator is two 64-bit words and a few bits more, and r,
  # which the key clamps so that its two words are multiples of 4 below
  # 2^60, folds the reduction modulo 2^130 - 5 into the product: the arrangement of
  # OpenSSL's `poly1305-armv8` and `poly1305-x86_64`.
  #
  # One block depends on the one before, and a block's multiplies and
  # reduction take about thirteen cycles in a row, while the processor could
  # start the multiplies of three blocks in that time. A long message is
  # therefore cut into four runs of equal length, each absorbed into an
  # accumulator of its own, side by side in one loop. Absorbing n blocks
  # multiplies everything before them by r^n, so the four accumulators add
  # up to the one-accumulator result once the first three are multiplied by
  # r^3q, r^2q and r^q, q being the length of a run; those powers take a
  # handful of general multiplications, done in limbs of 44, 44 and 42 bits
  # as `Poly1305OneTimeAuthenticator` does. The blocks left after the four
  # runs follow with one accumulator.
  #
  # On x86-64 processors with AVX2, whole blocks from
  # `SHORTEST_VECTOR_BLOCK_COUNT` on go to the vector instructions instead:
  # four lanes in limbs of 26 bits on AVX2
  # (`X8664CipherInstructions.absorb_poly1305_groups`), or eight lanes in
  # limbs of 44 bits on AVX-512 IFMA
  # (`absorb_poly1305_groups_with_fused_multiply_add`), with a table of the
  # powers of r this module computes in limbs of 44 bits.
  #
  # Every product is a wrapping 128-bit multiply of two 64-bit words, which
  # these processors run in a time that does not depend on the words, and
  # the final reduction picks its result with a mask. Nothing the key or the
  # message holds decides a branch or a memory address. Every buffer handed
  # to these methods is treated as secret. Sizes are public.
  module Poly1305WithWideMultiplication
    KEY_BYTESIZE   = 32
    TAG_BYTESIZE   = 16
    BLOCK_BYTESIZE = 16

    # Runs absorbed side by side, and the shortest run worth the
    # multiplications that join them.
    private RUN_COUNT                = 4
    private SHORTEST_RUN_BLOCK_COUNT = 8

    private LIMB_MASK_44 = 0xfffffffffff_u64
    private LIMB_MASK_42 = 0x3ffffffffff_u64

    # The clamp of RFC 8439 §2.5 on the two words of r.
    private CLAMP_LOW  = 0x0ffffffc0fffffff_u64
    private CLAMP_HIGH = 0x0ffffffc0ffffffc_u64

    {% if flag?(:x86_64) %}
      # Fewest whole blocks worth the table of powers the vector
      # instructions need, measured on the processors of GitHub's x86-64
      # runners.
      private SHORTEST_VECTOR_BLOCK_COUNT = 64

      private LIMB_MASK_26 = 0x3ffffff_u64

      # Words of the tables `X8664CipherInstructions.absorb_poly1305_groups`
      # (23 vectors of four words, then five sums) and
      # `absorb_poly1305_groups_with_fused_multiply_add` (up to 18 vectors of
      # eight words, then three sums) read.
      private FOUR_LANE_TABLE_WORD_COUNT          = 23 * 4 + 5
      private FUSED_MULTIPLY_ADD_TABLE_WORD_COUNT = 160

      # Words of that table the general-register blocks of a mixed pass
      # use (`absorb_poly1305_groups_with_fused_multiply_add`).
      private MIXED_TABLE_WORD = 152

      # From 1024 blocks (16 KiB), IFMA Poly1305 also absorbs four blocks a
      # pass on the general registers: 25% faster on the EPYC 9V74, whose
      # IFMA runs on half-width units, and 1 to 3% slower on the Xeon
      # 6975P-C; below 16 KiB the power of r that joins the two stretches
      # costs more than the blocks save.
      private SHORTEST_MIXED_BLOCK_COUNT = 1024
      private MIXED_BLOCKS_PER_PASS      =    4

      # Fewest whole blocks worth the sixteen powers of r that two sets of
      # IFMA lanes need.
      private SHORTEST_TWO_SET_BLOCK_COUNT = 256

      # The block each lane of a group holds, in the order the vector
      # instructions load them (see `absorb_poly1305_groups`).
      private BLOCK_OF_LANE_IN_FOUR  = {0, 2, 1, 3}
      private BLOCK_OF_LANE_IN_EIGHT = {0, 4, 1, 5, 2, 6, 3, 7}
    {% end %}

    # The accumulator: two full words and the bits above 2^128.
    private record Accumulator, low : UInt64, high : UInt64, top : UInt64

    # Writes into *tag* the tag RFC 8439 §2.8 defines for an encrypted
    # message: *associated_data* and *ciphertext*, each padded with zeros to
    # a whole block, then both lengths as 64-bit little-endian numbers.
    def self.authenticate_encrypted_message(key : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes) : Nil
      raise KeySizeMismatch.new("a Poly1305 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE
      raise OutputSizeMismatch.new("a Poly1305 tag is #{TAG_BYTESIZE} bytes") unless tag.size == TAG_BYTESIZE

      r0 = load_word(key.to_unsafe) & CLAMP_LOW
      r1 = load_word(key.to_unsafe + 8) & CLAMP_HIGH
      accumulator = Accumulator.new(0_u64, 0_u64, 0_u64)
      accumulator = absorb_padded(accumulator, r0, r1, associated_data)
      accumulator = absorb_padded(accumulator, r0, r1, ciphertext)
      accumulator = absorb_block(accumulator, r0, r1, associated_data.size.to_u64!, ciphertext.size.to_u64!)
      finish(accumulator, key, tag)
    end

    # Words of a state kept in memory, which the vector ChaCha20 assembly
    # can also absorb into: the accumulator (low, high, top), then r's two
    # words.
    STATE_WORD_COUNT = 5

    # Starts the state at *state* (`STATE_WORD_COUNT` words) for the
    # one-time *key*.
    def self.start(key : Bytes, state : Pointer(UInt64)) : Nil
      raise KeySizeMismatch.new("a Poly1305 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE

      state[0] = 0_u64
      state[1] = 0_u64
      state[2] = 0_u64
      state[3] = load_word(key.to_unsafe) & CLAMP_LOW
      state[4] = load_word(key.to_unsafe + 8) & CLAMP_HIGH
    end

    # Absorbs *data* into the state at *state*, as whole blocks with the
    # last one padded with zeros.
    def self.absorb_padded(state : Pointer(UInt64), data : Bytes) : Nil
      accumulator = absorb_padded(Accumulator.new(state[0], state[1], state[2]), state[3], state[4], data)
      state[0] = accumulator.low
      state[1] = accumulator.high
      state[2] = accumulator.top
    end

    # Absorbs the block of both lengths and writes the tag into *tag*.
    def self.finish_encrypted_message(state : Pointer(UInt64), key : Bytes, associated_data_bytesize : Int32,
                                      ciphertext_bytesize : Int32, tag : Bytes) : Nil
      raise OutputSizeMismatch.new("a Poly1305 tag is #{TAG_BYTESIZE} bytes") unless tag.size == TAG_BYTESIZE

      accumulator = absorb_block(Accumulator.new(state[0], state[1], state[2]), state[3], state[4],
        associated_data_bytesize.to_u64!, ciphertext_bytesize.to_u64!)
      finish(accumulator, key, tag)
    end

    # Absorbs *data* as whole blocks, the last one padded with zeros.
    private def self.absorb_padded(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, data : Bytes) : Accumulator
      whole_block_count = data.size // BLOCK_BYTESIZE
      accumulator = absorb_whole_blocks(accumulator, r0, r1, data.to_unsafe, whole_block_count)
      left_over = data.size - whole_block_count * BLOCK_BYTESIZE
      return accumulator if left_over == 0

      last_block_storage = StaticArray(UInt8, 16).new(0_u8)
      last_block = last_block_storage.to_slice
      data[whole_block_count * BLOCK_BYTESIZE, left_over].copy_to(last_block)
      accumulator = absorb_block(accumulator, r0, r1, load_word(last_block.to_unsafe), load_word(last_block.to_unsafe + 8))
      SecretWiping.wipe(last_block)
      accumulator
    end

    private def self.absorb_whole_blocks(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, blocks : Pointer(UInt8), block_count : Int32) : Accumulator
      {% if flag?(:x86_64) %}
        if ProcessorFeatures::HAS_AVX2 && block_count >= SHORTEST_VECTOR_BLOCK_COUNT
          if ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD && block_count >= SHORTEST_MIXED_BLOCK_COUNT
            mixed_count = MIXED_BLOCKS_PER_PASS
            # Groups of 16 vector blocks, and mixed_count blocks on the
            # general registers in each pass but the last.
            group_count = (block_count + mixed_count) // (16 + mixed_count)
            vector_block_count = group_count * 16
            scalar_block_count = (group_count - 1) * mixed_count
            vector_accumulator, scalar_accumulator = absorb_mixed_groups(accumulator, r0, r1, blocks, group_count, mixed_count)
            power = power_of(to_limbs(Accumulator.new(r0, r1, 0_u64)), scalar_block_count)
            accumulator = to_words(add_limbs(multiply_limbs(to_limbs(vector_accumulator), power), to_limbs(scalar_accumulator)))
            done = vector_block_count + scalar_block_count
          elsif ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD
            set_count = block_count >= SHORTEST_TWO_SET_BLOCK_COUNT ? 2 : 1
            group_count = block_count // (8 * set_count)
            accumulator = absorb_groups_with_fused_multiply_add(accumulator, r0, r1, blocks, group_count, set_count)
            done = group_count * 8 * set_count
          else
            group_count = block_count // 4
            accumulator = absorb_four_lane_groups(accumulator, r0, r1, blocks, group_count)
            done = group_count * 4
          end
          blocks += done * BLOCK_BYTESIZE
          block_count -= done
        end
      {% end %}
      run_block_count = block_count // RUN_COUNT
      done = 0
      if run_block_count >= SHORTEST_RUN_BLOCK_COUNT
        accumulator = absorb_four_runs(accumulator, r0, r1, blocks, run_block_count)
        done = run_block_count * RUN_COUNT
      end
      while done < block_count
        block = blocks + done * BLOCK_BYTESIZE
        accumulator = absorb_block(accumulator, r0, r1, load_word(block), load_word(block + 8))
        done += 1
      end
      accumulator
    end

    # h = (h + m + 2^128) * r, partly reduced.
    @[AlwaysInline]
    private def self.absorb_block(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, m0 : UInt64, m1 : UInt64) : Accumulator
      s1 = r1 &+ r1.unsafe_shr(2)
      sum = accumulator.low.to_u128! &+ m0
      h0 = sum.to_u64!
      sum = accumulator.high.to_u128! &+ m1 &+ sum.unsafe_shr(64)
      h1 = sum.to_u64!
      h2 = accumulator.top &+ sum.unsafe_shr(64).to_u64! &+ 1_u64
      multiply_by_r(h0, h1, h2, r0, r1, s1)
    end

    @[AlwaysInline]
    private def self.multiply_by_r(h0 : UInt64, h1 : UInt64, h2 : UInt64, r0 : UInt64, r1 : UInt64, s1 : UInt64) : Accumulator
      d0 = h0.to_u128! &* r0 &+ h1.to_u128! &* s1
      d1 = h0.to_u128! &* r1 &+ h1.to_u128! &* r0 &+ (h2 &* s1).to_u128! &+ d0.unsafe_shr(64)
      d2 = h2 &* r0 &+ d1.unsafe_shr(64).to_u64!
      # Bits from 2^130 up are worth 5 each: fold them back into the bottom.
      carry = d2.unsafe_shr(2) &+ (d2 & ~3_u64)
      sum = d0.to_u64!.to_u128! &+ carry
      low = sum.to_u64!
      sum = d1.to_u64!.to_u128! &+ sum.unsafe_shr(64)
      Accumulator.new(low, sum.to_u64!, (d2 & 3_u64) &+ sum.unsafe_shr(64).to_u64!)
    end

    # Absorbs 4 * *run_block_count* blocks as four runs side by side.
    private def self.absorb_four_runs(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, blocks : Pointer(UInt8), run_block_count : Int32) : Accumulator
      run_bytesize = run_block_count * BLOCK_BYTESIZE
      first = accumulator
      second = Accumulator.new(0_u64, 0_u64, 0_u64)
      third = second
      fourth = second
      index = 0
      while index < run_block_count
        block = blocks + index * BLOCK_BYTESIZE
        first = absorb_block(first, r0, r1, load_word(block), load_word(block + 8))
        block += run_bytesize
        second = absorb_block(second, r0, r1, load_word(block), load_word(block + 8))
        block += run_bytesize
        third = absorb_block(third, r0, r1, load_word(block), load_word(block + 8))
        block += run_bytesize
        fourth = absorb_block(fourth, r0, r1, load_word(block), load_word(block + 8))
        index += 1
      end

      # r^q, r^2q and r^3q in limbs of 44 bits; then the sum
      # first * r^3q + second * r^2q + third * r^q + fourth.
      power = to_limbs(Accumulator.new(r0, r1, 0_u64))
      power = power_of(power, run_block_count)
      double_power = multiply_limbs(power, power)
      triple_power = multiply_limbs(double_power, power)
      total = add_limbs(multiply_limbs(to_limbs(first), triple_power), multiply_limbs(to_limbs(second), double_power))
      total = add_limbs(total, multiply_limbs(to_limbs(third), power))
      total = add_limbs(total, to_limbs(fourth))
      to_words(total)
    end

    {% if flag?(:x86_64) %}
      # Absorbs *group_count* (at least 2) groups of four blocks on AVX2. The
      # table on the stack holds the accumulator, r^4 for every lane and,
      # for the last group, the power of r each lane ends with, all in limbs
      # of 26 bits with limbs 1 to 4 also times 5; it is wiped afterwards.
      @[NoInline]
      private def self.absorb_four_lane_groups(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, blocks : Pointer(UInt8),
                                               group_count : Int32) : Accumulator
        raise OutputSizeMismatch.new("the vector instructions take at least two groups") unless group_count >= 2

        table_storage = StaticArray(UInt64, FOUR_LANE_TABLE_WORD_COUNT).new(0_u64)
        table = table_storage.to_slice
        list_of_powers = powers_of_r(r0, r1, 4)
        put_26_bit_limbs(table, 0, 0, to_26_bit_limbs(accumulator))
        4.times do |lane|
          put_26_bit_limbs(table, 5, lane, to_26_bit_limbs(to_words(list_of_powers[3])))
          put_26_bit_limbs(table, 14, lane, to_26_bit_limbs(to_words(list_of_powers[3 - BLOCK_OF_LANE_IN_FOUR[lane]])))
        end

        table_pointer = table.to_unsafe
        X8664CipherInstructions.absorb_poly1305_groups(table_pointer, blocks, (group_count - 1).to_u64)
        sums = table_pointer + 23 * 4
        result = from_26_bit_limbs(sums[0], sums[1], sums[2], sums[3], sums[4])
        SecretWiping.wipe(table)
        result
      end

      # Absorbs *group_count* (at least 2) groups of 8 * *set_count* blocks
      # on AVX-512 IFMA, with a table like that of `absorb_four_lane_groups`
      # in limbs of 44, 44 and 42 bits, limbs 1 and 2 also times 20.
      @[NoInline]
      private def self.absorb_groups_with_fused_multiply_add(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, blocks : Pointer(UInt8),
                                                             group_count : Int32, set_count : Int32) : Accumulator
        raise OutputSizeMismatch.new("the vector instructions take at least two groups") unless group_count >= 2
        raise OutputSizeMismatch.new("the vector instructions run one or two sets of lanes") unless set_count == 1 || set_count == 2

        # Every word the statement reads is written below: lane 0 of the
        # accumulator's vectors and zeros in its other lanes, then the
        # powers.
        table_storage = uninitialized UInt64[FUSED_MULTIPLY_ADD_TABLE_WORD_COUNT]
        table_pointer = table_storage.to_unsafe
        table = table_storage.to_slice[0, (8 + 5 * set_count) * 8 + 3]
        lane_count = 8 * set_count
        list_of_powers = powers_of_r(r0, r1, lane_count)
        limbs = to_limbs(accumulator)
        Intrinsics.memset(table_pointer.as(Void*), 0_u8, 3 * 64, false)
        3.times { |limb| table_pointer[limb * 8] = limbs[limb] }
        8.times do |lane|
          put_44_bit_limbs(table_pointer, 3, lane, list_of_powers[lane_count - 1])
          set_count.times do |set|
            block = 8 * set + BLOCK_OF_LANE_IN_EIGHT[lane]
            put_44_bit_limbs(table_pointer, 8 + 5 * set, lane, list_of_powers[lane_count - 1 - block])
          end
        end

        if set_count == 2
          X8664CipherInstructions.absorb_poly1305_groups_with_fused_multiply_add(table_pointer, blocks, (group_count - 1).to_u64, 2)
        else
          X8664CipherInstructions.absorb_poly1305_groups_with_fused_multiply_add(table_pointer, blocks, (group_count - 1).to_u64, 1)
        end
        sums = table_pointer + (8 + 5 * set_count) * 8
        result = from_44_bit_limbs(sums[0], sums[1], sums[2])
        SecretWiping.wipe(table)
        result
      end

      # Absorbs *group_count* (at least 2) groups of 16 blocks on IFMA (two
      # sets) from *accumulator* and, meanwhile, the *mixed_count* blocks a
      # pass after them on the general registers from zero; returns both
      # accumulators.
      @[NoInline]
      private def self.absorb_mixed_groups(accumulator : Accumulator, r0 : UInt64, r1 : UInt64, blocks : Pointer(UInt8),
                                           group_count : Int32, mixed_count : Int32) : {Accumulator, Accumulator}
        raise OutputSizeMismatch.new("the vector instructions take at least two groups") unless group_count >= 2

        table_storage = uninitialized UInt64[FUSED_MULTIPLY_ADD_TABLE_WORD_COUNT]
        table_pointer = table_storage.to_unsafe
        table = table_storage.to_slice
        list_of_powers = powers_of_r(r0, r1, 16)
        limbs = to_limbs(accumulator)
        Intrinsics.memset(table_pointer.as(Void*), 0_u8, 3 * 64, false)
        3.times { |limb| table_pointer[limb * 8] = limbs[limb] }
        8.times do |lane|
          put_44_bit_limbs(table_pointer, 3, lane, list_of_powers[15])
          2.times do |set|
            block = 8 * set + BLOCK_OF_LANE_IN_EIGHT[lane]
            put_44_bit_limbs(table_pointer, 8 + 5 * set, lane, list_of_powers[15 - block])
          end
        end
        mixed = table_pointer + MIXED_TABLE_WORD
        mixed[0] = r0
        mixed[1] = r1
        mixed[2] = r1 &+ r1.unsafe_shr(2)
        mixed[3] = 0_u64
        mixed[4] = 0_u64
        mixed[5] = 0_u64
        mixed[6] = (blocks + group_count * 16 * BLOCK_BYTESIZE).address
        mixed[7] = blocks.address

        raise OutputSizeMismatch.new("the mixed statement absorbs #{MIXED_BLOCKS_PER_PASS} blocks a pass") unless mixed_count == MIXED_BLOCKS_PER_PASS
        X8664CipherInstructions.absorb_poly1305_groups_with_fused_multiply_add(table_pointer, nil, (group_count - 1).to_u64, 2, 4)
        sums = table_pointer + 18 * 8
        vector_accumulator = from_44_bit_limbs(sums[0], sums[1], sums[2])
        scalar_accumulator = Accumulator.new(mixed[3], mixed[4], mixed[5])
        SecretWiping.wipe(table)
        {vector_accumulator, scalar_accumulator}
      end

      # r, r^2, ... r^count (count 4, 8 or 16) in limbs of 44, 44 and 42
      # bits; the entries after r^count are left at r. Each power from r^3
      # on multiplies two earlier ones, so the chain of multiplies to r^16
      # is four long.
      private def self.powers_of_r(r0 : UInt64, r1 : UInt64, count : Int32) : StaticArray({UInt64, UInt64, UInt64}, 16)
        r = to_limbs(Accumulator.new(r0, r1, 0_u64))
        list_of_powers = StaticArray({UInt64, UInt64, UInt64}, 16).new(r)
        list_of_powers[1] = multiply_limbs(r, r)
        list_of_powers[2] = multiply_limbs(list_of_powers[1], r)
        list_of_powers[3] = multiply_limbs(list_of_powers[1], list_of_powers[1])
        half = 4
        while half < count
          half.times { |index| list_of_powers[half + index] = multiply_limbs(list_of_powers[half - 1], list_of_powers[index]) }
          half *= 2
        end
        list_of_powers
      end

      # Writes *limbs* into lane *lane* of the five vectors (four words
      # each) from *first_vector* and, when that is a power, limbs 1 to 4
      # times 5 into the four vectors after them.
      private def self.put_26_bit_limbs(table : Slice(UInt64), first_vector : Int32, lane : Int32,
                                        limbs : {UInt64, UInt64, UInt64, UInt64, UInt64}) : Nil
        5.times { |limb| table[(first_vector + limb) * 4 + lane] = limbs[limb] }
        return if first_vector == 0

        (1...5).each { |limb| table[(first_vector + 4 + limb) * 4 + lane] = limbs[limb] &* 5_u64 }
      end

      # Writes the power *limbs* into lane *lane* of the three vectors
      # (eight words each) from *first_vector*, then limbs 1 and 2 times 20.
      private def self.put_44_bit_limbs(table : Pointer(UInt64), first_vector : Int32, lane : Int32, limbs : {UInt64, UInt64, UInt64}) : Nil
        3.times { |limb| table[(first_vector + limb) * 8 + lane] = limbs[limb] }
        table[(first_vector + 3) * 8 + lane] = limbs[1] &* 20_u64
        table[(first_vector + 4) * 8 + lane] = limbs[2] &* 20_u64
      end

      private def self.to_26_bit_limbs(accumulator : Accumulator) : {UInt64, UInt64, UInt64, UInt64, UInt64}
        {accumulator.low & LIMB_MASK_26,
         accumulator.low.unsafe_shr(26) & LIMB_MASK_26,
         (accumulator.low.unsafe_shr(52) | accumulator.high.unsafe_shl(12)) & LIMB_MASK_26,
         accumulator.high.unsafe_shr(14) & LIMB_MASK_26,
         accumulator.high.unsafe_shr(40) | accumulator.top.unsafe_shl(24)}
      end

      # The accumulator from limbs of 26 bits that may hold a few bits more.
      private def self.from_26_bit_limbs(limb0 : UInt64, limb1 : UInt64, limb2 : UInt64, limb3 : UInt64, limb4 : UInt64) : Accumulator
        sum = limb0.to_u128! &+ limb1.to_u128!.unsafe_shl(26) &+ limb2.to_u128!.unsafe_shl(52)
        low = sum.to_u64!
        sum = sum.unsafe_shr(64) &+ limb3.to_u128!.unsafe_shl(14) &+ limb4.to_u128!.unsafe_shl(40)
        fold_top(low, sum.to_u64!, sum.unsafe_shr(64).to_u64!)
      end

      # The accumulator from limbs of 44, 44 and 42 bits that may hold a few
      # bits more.
      private def self.from_44_bit_limbs(limb0 : UInt64, limb1 : UInt64, limb2 : UInt64) : Accumulator
        sum = limb0.to_u128! &+ limb1.to_u128!.unsafe_shl(44)
        low = sum.to_u64!
        sum = sum.unsafe_shr(64) &+ limb2.to_u128!.unsafe_shl(24)
        fold_top(low, sum.to_u64!, sum.unsafe_shr(64).to_u64!)
      end

      # Folds the bits of *top* from 2^130 up back into the bottom, times 5,
      # so that the top word is at most 4, as `multiply_by_r` needs.
      private def self.fold_top(low : UInt64, high : UInt64, top : UInt64) : Accumulator
        sum = low.to_u128! &+ top.unsafe_shr(2) &* 5_u64
        low = sum.to_u64!
        sum = high.to_u128! &+ sum.unsafe_shr(64)
        Accumulator.new(low, sum.to_u64!, (top & 3_u64) &+ sum.unsafe_shr(64).to_u64!)
      end
    {% end %}

    # *base* raised to *exponent* (at least 1), by squaring and multiplying.
    # The exponent is a length, which is public.
    private def self.power_of(base : {UInt64, UInt64, UInt64}, exponent : Int32) : {UInt64, UInt64, UInt64}
      result = base
      bit = 31 - exponent.leading_zeros_count
      while bit > 0
        bit -= 1
        result = multiply_limbs(result, result)
        result = multiply_limbs(result, base) if (exponent >> bit) & 1 == 1
      end
      result
    end

    # The accumulator in limbs of 44, 44 and 42 bits (the top limb may hold
    # a few bits more, which the limb multiply allows).
    private def self.to_limbs(accumulator : Accumulator) : {UInt64, UInt64, UInt64}
      {accumulator.low & LIMB_MASK_44,
       (accumulator.low.unsafe_shr(44) | accumulator.high.unsafe_shl(20)) & LIMB_MASK_44,
       accumulator.high.unsafe_shr(24) | accumulator.top.unsafe_shl(40)}
    end

    private def self.to_words(limbs : {UInt64, UInt64, UInt64}) : Accumulator
      limb1 = limbs[1] & LIMB_MASK_44
      limb2 = limbs[2] &+ limbs[1].unsafe_shr(44)
      Accumulator.new(limbs[0] | limb1.unsafe_shl(44), limb1.unsafe_shr(20) | limb2.unsafe_shl(24), limb2.unsafe_shr(40))
    end

    private def self.add_limbs(a : {UInt64, UInt64, UInt64}, b : {UInt64, UInt64, UInt64}) : {UInt64, UInt64, UInt64}
      sum0 = a[0] &+ b[0]
      sum1 = a[1] &+ b[1] &+ sum0.unsafe_shr(44)
      sum2 = a[2] &+ b[2] &+ sum1.unsafe_shr(44)
      sum0 = (sum0 & LIMB_MASK_44) &+ sum2.unsafe_shr(42) &* 5_u64
      sum2 &= LIMB_MASK_42
      sum1 = (sum1 & LIMB_MASK_44) &+ sum0.unsafe_shr(44)
      {sum0 & LIMB_MASK_44, sum1, sum2}
    end

    # a * b modulo 2^130 - 5 for any a and b in limbs, as poly1305-donna
    # multiplies: 2^132 is 20 modulo 2^130 - 5.
    private def self.multiply_limbs(a : {UInt64, UInt64, UInt64}, b : {UInt64, UInt64, UInt64}) : {UInt64, UInt64, UInt64}
      s1 = b[1] &* 20_u64
      s2 = b[2] &* 20_u64
      d0 = a[0].to_u128! &* b[0] &+ a[1].to_u128! &* s2 &+ a[2].to_u128! &* s1
      d1 = a[0].to_u128! &* b[1] &+ a[1].to_u128! &* b[0] &+ a[2].to_u128! &* s2
      d2 = a[0].to_u128! &* b[2] &+ a[1].to_u128! &* b[1] &+ a[2].to_u128! &* b[0]
      d1 &+= d0.unsafe_shr(44)
      limb0 = d0.to_u64! & LIMB_MASK_44
      d2 &+= d1.unsafe_shr(44)
      limb1 = d1.to_u64! & LIMB_MASK_44
      limb2 = d2.to_u64! & LIMB_MASK_42
      limb0 &+= d2.unsafe_shr(42).to_u64! &* 5_u64
      limb1 &+= limb0.unsafe_shr(44)
      {limb0 & LIMB_MASK_44, limb1, limb2}
    end

    # The tag: h reduced modulo 2^130 - 5, plus the second half of the key,
    # modulo 2^128.
    private def self.finish(accumulator : Accumulator, key : Bytes, tag : Bytes) : Nil
      # Fully reduce: h is below 2^131 here, so fold the top once more.
      carry = accumulator.top.unsafe_shr(2) &* 5_u64
      sum = accumulator.low.to_u128! &+ carry
      h0 = sum.to_u64!
      sum = accumulator.high.to_u128! &+ sum.unsafe_shr(64)
      h1 = sum.to_u64!
      h2 = (accumulator.top & 3_u64) &+ sum.unsafe_shr(64).to_u64!

      # g = h + 5; h - p is g - 2^130, so take g when it reaches 2^130.
      sum = h0.to_u128! &+ 5_u64
      g0 = sum.to_u64!
      sum = h1.to_u128! &+ sum.unsafe_shr(64)
      g1 = sum.to_u64!
      g2 = h2 &+ sum.unsafe_shr(64).to_u64!
      take_g = 0_u64 &- g2.unsafe_shr(2)
      h0 = (h0 & ~take_g) | (g0 & take_g)
      h1 = (h1 & ~take_g) | (g1 & take_g)

      sum = h0.to_u128! &+ load_word(key.to_unsafe + 16)
      store_word(tag.to_unsafe, sum.to_u64!)
      sum = h1.to_u128! &+ load_word(key.to_unsafe + 24) &+ sum.unsafe_shr(64)
      store_word(tag.to_unsafe + 8, sum.to_u64!)
    end

    @[AlwaysInline]
    private def self.load_word(bytes : Pointer(UInt8)) : UInt64
      bytes.as(UInt64*).value
    end

    @[AlwaysInline]
    private def self.store_word(bytes : Pointer(UInt8), word : UInt64) : Nil
      bytes.as(UInt64*).value = word
    end
  end
end
