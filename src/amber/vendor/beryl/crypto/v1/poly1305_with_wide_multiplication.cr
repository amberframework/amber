require "../error"
require "../secret_wiping"

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
