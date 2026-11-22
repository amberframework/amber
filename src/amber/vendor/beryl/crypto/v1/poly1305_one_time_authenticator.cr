require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # Poly1305 (RFC 8439 §2.5): a message authentication code whose key may
  # authenticate one message only. ChaCha20-Poly1305 derives a fresh key for
  # every nonce, which is the only way this shard uses it.
  #
  # The accumulator is kept in three limbs of 44, 44 and 42 bits (the layout
  # of poly1305-donna by Andrew Moon, public domain), every product is a
  # wrapping 128-bit multiply, and the final reduction picks its result with
  # a mask. Nothing the key or the message holds decides a branch or a memory
  # address.
  #
  # Every buffer handed to these methods is treated as secret. Sizes are
  # public.
  module Poly1305OneTimeAuthenticator
    KEY_BYTESIZE   = 32
    TAG_BYTESIZE   = 16
    BLOCK_BYTESIZE = 16

    # Words of working state: the accumulator (3), r (3) and the two
    # multiples of r that fold the reduction into the product (2).
    STATE_WORD_COUNT = 8

    private LIMB_MASK_44 = 0xfffffffffff_u64
    private LIMB_MASK_42 = 0x3ffffffffff_u64

    # Bit 128 of a full block, in the third limb.
    private HIGH_BIT = 1_u64 << 40

    # Writes into *tag* (16 bytes) the Poly1305 tag of *message* under the
    # one-time *key* (32 bytes).
    def self.authenticate(key : Bytes, message : Bytes, tag : Bytes) : Nil
      state_storage = uninitialized UInt64[8]
      state = state_storage.to_unsafe
      load_key(state, key)
      absorb(state, message, false)
      finish(state, key, tag)
      SecretWiping.wipe(Bytes.new(state.as(UInt8*), 64))
    end

    # Writes into *tag* the tag RFC 8439 §2.8 defines for an encrypted
    # message: *associated_data* and *ciphertext*, each padded with zeros to
    # a whole block, then both lengths as 64-bit little-endian numbers.
    def self.authenticate_encrypted_message(key : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes) : Nil
      state_storage = uninitialized UInt64[8]
      state = state_storage.to_unsafe
      load_key(state, key)
      absorb(state, associated_data, true)
      absorb(state, ciphertext, true)

      length_block_storage = uninitialized UInt8[16]
      length_block = length_block_storage.to_unsafe
      store_word(length_block, associated_data.size.to_u64!)
      store_word(length_block + 8, ciphertext.size.to_u64!)
      absorb(state, length_block_storage.to_slice, true)

      finish(state, key, tag)
      SecretWiping.wipe(Bytes.new(state.as(UInt8*), 64))
    end

    private def self.load_key(state : Pointer(UInt64), key : Bytes) : Nil
      raise KeySizeMismatch.new("a Poly1305 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE

      low_word = load_word(key.to_unsafe)
      high_word = load_word(key.to_unsafe + 8)
      # r is clamped as RFC 8439 §2.5.1 requires.
      r0 = low_word & 0xffc0fffffff_u64
      r1 = ((low_word >> 44) | (high_word << 20)) & 0xfffffc0ffff_u64
      r2 = (high_word >> 24) & 0x00ffffffc0f_u64

      state[0] = 0_u64
      state[1] = 0_u64
      state[2] = 0_u64
      state[3] = r0
      state[4] = r1
      state[5] = r2
      state[6] = r1 &* 20_u64
      state[7] = r2 &* 20_u64
    end

    # Mixes *data* into the accumulator. A last block that is not full is
    # padded with zeros when *is_padded_with_zeros* (the layout inside an
    # encrypted message), or closed with a single 1 bit (the end of a plain
    # message).
    private def self.absorb(state : Pointer(UInt64), data : Bytes, is_padded_with_zeros : Bool) : Nil
      h0 = state[0]
      h1 = state[1]
      h2 = state[2]
      r0 = state[3]
      r1 = state[4]
      r2 = state[5]
      s1 = state[6]
      s2 = state[7]

      last_block_storage = uninitialized UInt8[16]
      last_block = last_block_storage.to_unsafe
      source = data.to_unsafe
      bytes_left = data.size
      while bytes_left > 0
        block = source
        high_bit = HIGH_BIT
        if bytes_left < BLOCK_BYTESIZE
          BLOCK_BYTESIZE.times { |index| last_block[index] = 0_u8 }
          bytes_left.times { |index| last_block[index] = source[index] }
          unless is_padded_with_zeros
            last_block[bytes_left] = 1_u8
            high_bit = 0_u64
          end
          block = last_block
          bytes_left = 0
        else
          source += BLOCK_BYTESIZE
          bytes_left -= BLOCK_BYTESIZE
        end

        low_word = load_word(block)
        high_word = load_word(block + 8)
        h0 &+= low_word & LIMB_MASK_44
        h1 &+= ((low_word >> 44) | (high_word << 20)) & LIMB_MASK_44
        h2 &+= ((high_word >> 24) & LIMB_MASK_42) | high_bit

        d0 = h0.to_u128! &* r0 &+ h1.to_u128! &* s2 &+ h2.to_u128! &* s1
        d1 = h0.to_u128! &* r1 &+ h1.to_u128! &* r0 &+ h2.to_u128! &* s2
        d2 = h0.to_u128! &* r2 &+ h1.to_u128! &* r1 &+ h2.to_u128! &* r0

        carry = (d0 >> 44).to_u64!
        h0 = d0.to_u64! & LIMB_MASK_44
        d1 &+= carry
        carry = (d1 >> 44).to_u64!
        h1 = d1.to_u64! & LIMB_MASK_44
        d2 &+= carry
        carry = (d2 >> 42).to_u64!
        h2 = d2.to_u64! & LIMB_MASK_42
        h0 &+= carry &* 5_u64
        carry = h0 >> 44
        h0 &= LIMB_MASK_44
        h1 &+= carry
      end

      state[0] = h0
      state[1] = h1
      state[2] = h2
      SecretWiping.wipe(last_block_storage.to_slice)
    end

    # Reduces the accumulator modulo 2^130 - 5, adds the second half of the
    # key and writes the tag.
    private def self.finish(state : Pointer(UInt64), key : Bytes, tag : Bytes) : Nil
      raise OutputSizeMismatch.new("a Poly1305 tag is #{TAG_BYTESIZE} bytes, the buffer holds #{tag.size}") unless tag.size == TAG_BYTESIZE

      h0 = state[0]
      h1 = state[1]
      h2 = state[2]

      carry = h1 >> 44
      h1 &= LIMB_MASK_44
      h2 &+= carry
      carry = h2 >> 42
      h2 &= LIMB_MASK_42
      h0 &+= carry &* 5_u64
      carry = h0 >> 44
      h0 &= LIMB_MASK_44
      h1 &+= carry
      carry = h1 >> 44
      h1 &= LIMB_MASK_44
      h2 &+= carry
      carry = h2 >> 42
      h2 &= LIMB_MASK_42
      h0 &+= carry &* 5_u64
      carry = h0 >> 44
      h0 &= LIMB_MASK_44
      h1 &+= carry

      # g = h + 5 - 2^130. When that is not negative, h was at least the
      # modulus and g is the reduced value; a mask picks between the two.
      g0 = h0 &+ 5_u64
      carry = g0 >> 44
      g0 &= LIMB_MASK_44
      g1 = h1 &+ carry
      carry = g1 >> 44
      g1 &= LIMB_MASK_44
      g2 = h2 &+ carry &- (1_u64 << 42)

      takes_g = (g2 >> 63) &- 1_u64
      keeps_h = ~takes_g
      h0 = (h0 & keeps_h) | (g0 & takes_g)
      h1 = (h1 & keeps_h) | (g1 & takes_g)
      h2 = (h2 & keeps_h) | (g2 & takes_g)

      low_word = load_word(key.to_unsafe + 16)
      high_word = load_word(key.to_unsafe + 24)
      h0 &+= low_word & LIMB_MASK_44
      carry = h0 >> 44
      h0 &= LIMB_MASK_44
      h1 &+= (((low_word >> 44) | (high_word << 20)) & LIMB_MASK_44) &+ carry
      carry = h1 >> 44
      h1 &= LIMB_MASK_44
      h2 &+= ((high_word >> 24) & LIMB_MASK_42) &+ carry
      h2 &= LIMB_MASK_42

      store_word(tag.to_unsafe, h0 | (h1 << 44))
      store_word(tag.to_unsafe + 8, (h1 >> 20) | (h2 << 24))
    end

    @[AlwaysInline]
    private def self.load_word(bytes : Pointer(UInt8)) : UInt64
      word = 0_u64
      8.times { |index| word |= bytes[index].to_u64! << (index * 8) }
      word
    end

    @[AlwaysInline]
    private def self.store_word(bytes : Pointer(UInt8), word : UInt64) : Nil
      8.times { |index| bytes[index] = (word >> (index * 8)).to_u8! }
    end
  end
end
