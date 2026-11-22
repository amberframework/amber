require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # GHASH, the authentication function of GCM (NIST SP 800-38D §6.4): a
  # polynomial evaluated in the field of 2^128 elements. The field multiply
  # is carry-less; here it is built from ordinary integer multiplies on
  # words whose bits are spaced four apart, so that carries never reach a
  # bit that is kept. No table is read and nothing the key or the data holds
  # decides a branch or a memory address.
  #
  # The design is BearSSL's `ghash_ctmul64` (Thomas Pornin, MIT license,
  # https://www.bearssl.org/constanttime.html), translated to Crystal.
  #
  # Every buffer handed to these methods is treated as secret. Sizes are
  # public.
  module GaloisHash
    BLOCK_BYTESIZE = 16

    # Words of working state: the accumulator (2) and the hash key in the
    # six forms the multiply reads (6).
    STATE_WORD_COUNT = 8

    # Sets *state* to an empty accumulator under *hash_key* (16 bytes, the
    # encryption of the all-zero block).
    def self.load_key(state : Slice(UInt64), hash_key : Bytes) : Nil
      raise OutputSizeMismatch.new("GHASH keeps #{STATE_WORD_COUNT} words of state") unless state.size == STATE_WORD_COUNT
      raise KeySizeMismatch.new("a GHASH key is #{BLOCK_BYTESIZE} bytes, not #{hash_key.size}") unless hash_key.size == BLOCK_BYTESIZE

      words = state.to_unsafe
      h1 = load_word(hash_key.to_unsafe)
      h0 = load_word(hash_key.to_unsafe + 8)
      h0_reversed = reverse_bits(h0)
      h1_reversed = reverse_bits(h1)
      words[0] = 0_u64
      words[1] = 0_u64
      words[2] = h0
      words[3] = h1
      words[4] = h0_reversed
      words[5] = h1_reversed
      words[6] = h0 ^ h1
      words[7] = h0_reversed ^ h1_reversed
    end

    # Empties the accumulator and keeps the key.
    def self.restart(state : Slice(UInt64)) : Nil
      state.to_unsafe[0] = 0_u64
      state.to_unsafe[1] = 0_u64
    end

    # Mixes *data* into the accumulator; a last block that is not full is
    # padded with zeros.
    def self.absorb(state : Slice(UInt64), data : Bytes) : Nil
      raise OutputSizeMismatch.new("GHASH keeps #{STATE_WORD_COUNT} words of state") unless state.size == STATE_WORD_COUNT

      words = state.to_unsafe
      y0 = words[0]
      y1 = words[1]
      h0 = words[2]
      h1 = words[3]
      h0_reversed = words[4]
      h1_reversed = words[5]
      h2 = words[6]
      h2_reversed = words[7]

      last_block_storage = uninitialized UInt8[16]
      last_block = last_block_storage.to_unsafe
      source = data.to_unsafe
      bytes_left = data.size
      while bytes_left > 0
        block = source
        if bytes_left < BLOCK_BYTESIZE
          BLOCK_BYTESIZE.times { |index| last_block[index] = 0_u8 }
          bytes_left.times { |index| last_block[index] = source[index] }
          block = last_block
          bytes_left = 0
        else
          source += BLOCK_BYTESIZE
          bytes_left -= BLOCK_BYTESIZE
        end

        y1 ^= load_word(block)
        y0 ^= load_word(block + 8)

        y0_reversed = reverse_bits(y0)
        y1_reversed = reverse_bits(y1)
        y2 = y0 ^ y1
        y2_reversed = y0_reversed ^ y1_reversed

        # Karatsuba: three multiplies give the low halves of the product,
        # three more on bit-reversed operands give the high halves.
        z0 = multiply_without_carries(y0, h0)
        z1 = multiply_without_carries(y1, h1)
        z2 = multiply_without_carries(y2, h2)
        z0_high = multiply_without_carries(y0_reversed, h0_reversed)
        z1_high = multiply_without_carries(y1_reversed, h1_reversed)
        z2_high = multiply_without_carries(y2_reversed, h2_reversed)
        z2 ^= z0 ^ z1
        z2_high ^= z0_high ^ z1_high
        z0_high = reverse_bits(z0_high) >> 1
        z1_high = reverse_bits(z1_high) >> 1
        z2_high = reverse_bits(z2_high) >> 1

        v0 = z0
        v1 = z0_high ^ z2
        v2 = z1 ^ z2_high
        v3 = z1_high

        # GCM numbers bits in the opposite order, which shifts the 255-bit
        # product left by one.
        v3 = (v3 << 1) | (v2 >> 63)
        v2 = (v2 << 1) | (v1 >> 63)
        v1 = (v1 << 1) | (v0 >> 63)
        v0 = v0 << 1

        # Reduction modulo x^128 + x^7 + x^2 + x + 1.
        v2 ^= v0 ^ (v0 >> 1) ^ (v0 >> 2) ^ (v0 >> 7)
        v1 ^= (v0 << 63) ^ (v0 << 62) ^ (v0 << 57)
        v3 ^= v1 ^ (v1 >> 1) ^ (v1 >> 2) ^ (v1 >> 7)
        v2 ^= (v1 << 63) ^ (v1 << 62) ^ (v1 << 57)

        y0 = v2
        y1 = v3
      end

      words[0] = y0
      words[1] = y1
      SecretWiping.wipe(last_block_storage.to_slice)
    end

    # Writes the accumulator into *digest* (16 bytes).
    def self.write_digest(state : Slice(UInt64), digest : Bytes) : Nil
      raise OutputSizeMismatch.new("a GHASH digest is #{BLOCK_BYTESIZE} bytes, the buffer holds #{digest.size}") unless digest.size == BLOCK_BYTESIZE

      store_word(digest.to_unsafe, state.to_unsafe[1])
      store_word(digest.to_unsafe + 8, state.to_unsafe[0])
    end

    # Returns the low 64 bits of the carry-less product of *first* and
    # *second*. Each operand is split into four words that keep every fourth
    # bit; in a product of two such words the carries of the integer multiply
    # stay inside the three unused bits between kept positions.
    @[AlwaysInline]
    private def self.multiply_without_carries(first : UInt64, second : UInt64) : UInt64
      x0 = first & 0x1111111111111111_u64
      x1 = first & 0x2222222222222222_u64
      x2 = first & 0x4444444444444444_u64
      x3 = first & 0x8888888888888888_u64
      y0 = second & 0x1111111111111111_u64
      y1 = second & 0x2222222222222222_u64
      y2 = second & 0x4444444444444444_u64
      y3 = second & 0x8888888888888888_u64
      z0 = (x0 &* y0) ^ (x1 &* y3) ^ (x2 &* y2) ^ (x3 &* y1)
      z1 = (x0 &* y1) ^ (x1 &* y0) ^ (x2 &* y3) ^ (x3 &* y2)
      z2 = (x0 &* y2) ^ (x1 &* y1) ^ (x2 &* y0) ^ (x3 &* y3)
      z3 = (x0 &* y3) ^ (x1 &* y2) ^ (x2 &* y1) ^ (x3 &* y0)
      (z0 & 0x1111111111111111_u64) | (z1 & 0x2222222222222222_u64) |
        (z2 & 0x4444444444444444_u64) | (z3 & 0x8888888888888888_u64)
    end

    @[AlwaysInline]
    private def self.reverse_bits(word : UInt64) : UInt64
      word = ((word & 0x5555555555555555_u64) << 1) | ((word >> 1) & 0x5555555555555555_u64)
      word = ((word & 0x3333333333333333_u64) << 2) | ((word >> 2) & 0x3333333333333333_u64)
      word = ((word & 0x0f0f0f0f0f0f0f0f_u64) << 4) | ((word >> 4) & 0x0f0f0f0f0f0f0f0f_u64)
      word = ((word & 0x00ff00ff00ff00ff_u64) << 8) | ((word >> 8) & 0x00ff00ff00ff00ff_u64)
      word = ((word & 0x0000ffff0000ffff_u64) << 16) | ((word >> 16) & 0x0000ffff0000ffff_u64)
      (word << 32) | (word >> 32)
    end

    # Reads a 64-bit big-endian word.
    @[AlwaysInline]
    private def self.load_word(bytes : Pointer(UInt8)) : UInt64
      word = 0_u64
      8.times { |index| word = (word << 8) | bytes[index].to_u64! }
      word
    end

    # Writes a 64-bit big-endian word.
    @[AlwaysInline]
    private def self.store_word(bytes : Pointer(UInt8), word : UInt64) : Nil
      8.times { |index| bytes[index] = (word >> (56 - index * 8)).to_u8! }
    end
  end
end
