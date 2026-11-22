require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # The ChaCha20 stream cipher (RFC 8439 §2.3 and §2.4) and HChaCha20, the
  # key derivation XChaCha20 is built on (draft-irtf-cfrg-xchacha-03 §2.2).
  # ChaCha20 is additions, XORs and rotations by fixed amounts on 32-bit
  # words, so nothing the key or the data holds decides a branch or a memory
  # address.
  #
  # Every buffer handed to these methods is treated as secret. Sizes and the
  # block counter are public.
  module ChaCha20StreamCipher
    KEY_BYTESIZE   = 32
    NONCE_BYTESIZE = 12
    BLOCK_BYTESIZE = 64

    # HChaCha20 takes the first 16 bytes of an XChaCha20 nonce.
    SUBKEY_NONCE_BYTESIZE = 16

    # "expand 32-byte k", the four constant words of the state.
    private CONSTANT_WORD_0 = 0x61707865_u32
    private CONSTANT_WORD_1 = 0x3320646e_u32
    private CONSTANT_WORD_2 = 0x79622d32_u32
    private CONSTANT_WORD_3 = 0x6b206574_u32

    private macro quarter_round(a, b, c, d)
      x{{ a }} &+= x{{ b }}
      x{{ d }} = (x{{ d }} ^ x{{ a }}).rotate_left(16)
      x{{ c }} &+= x{{ d }}
      x{{ b }} = (x{{ b }} ^ x{{ c }}).rotate_left(12)
      x{{ a }} &+= x{{ b }}
      x{{ d }} = (x{{ d }} ^ x{{ a }}).rotate_left(8)
      x{{ c }} &+= x{{ d }}
      x{{ b }} = (x{{ b }} ^ x{{ c }}).rotate_left(7)
    end

    # Runs the twenty rounds on the sixteen words at *state* and writes the
    # result to *permuted*; *state* is left as it was.
    @[AlwaysInline]
    private def self.run_twenty_rounds(state : Pointer(UInt32), permuted : Pointer(UInt32)) : Nil
      {% for index in 0...16 %}
        x{{ index }} = state[{{ index }}]
      {% end %}
      double_round = 0
      while double_round < 10
        quarter_round(0, 4, 8, 12)
        quarter_round(1, 5, 9, 13)
        quarter_round(2, 6, 10, 14)
        quarter_round(3, 7, 11, 15)
        quarter_round(0, 5, 10, 15)
        quarter_round(1, 6, 11, 12)
        quarter_round(2, 7, 8, 13)
        quarter_round(3, 4, 9, 14)
        double_round += 1
      end
      {% for index in 0...16 %}
        permuted[{{ index }}] = x{{ index }}
      {% end %}
    end

    # XORs *input* into *output* with the keystream of *key* and *nonce*,
    # starting at block number *initial_counter*.
    def self.xor_keystream(key : Bytes, nonce : Bytes, initial_counter : UInt32, input : Bytes, output : Bytes) : Nil
      raise KeySizeMismatch.new("a ChaCha20 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE
      raise NonceSizeMismatch.new("a ChaCha20 nonce is #{NONCE_BYTESIZE} bytes, not #{nonce.size}") unless nonce.size == NONCE_BYTESIZE
      raise OutputSizeMismatch.new("a stream cipher writes as many bytes as it reads") unless input.size == output.size
      blocks_available = (1_u64 << 32) - initial_counter
      if input.size.to_u64 > blocks_available * BLOCK_BYTESIZE
        raise MessageTooLong.new("ChaCha20 counts #{blocks_available} blocks from block #{initial_counter}, the message needs more")
      end

      state_storage = uninitialized UInt32[16]
      state = state_storage.to_unsafe
      state[0] = CONSTANT_WORD_0
      state[1] = CONSTANT_WORD_1
      state[2] = CONSTANT_WORD_2
      state[3] = CONSTANT_WORD_3
      8.times { |index| state[4 + index] = load_word(key.to_unsafe + index * 4) }
      state[12] = initial_counter
      3.times { |index| state[13 + index] = load_word(nonce.to_unsafe + index * 4) }

      permuted_storage = uninitialized UInt32[16]
      permuted = permuted_storage.to_unsafe
      keystream_storage = uninitialized UInt8[64]
      keystream = keystream_storage.to_unsafe
      source = input.to_unsafe
      destination = output.to_unsafe
      bytes_left = input.size
      while bytes_left > 0
        run_twenty_rounds(state, permuted)
        16.times { |index| store_word(keystream + index * 4, permuted[index] &+ state[index]) }
        state[12] &+= 1_u32

        bytes_taken = Math.min(bytes_left, BLOCK_BYTESIZE)
        bytes_taken.times { |index| destination[index] = source[index] ^ keystream[index] }
        source += bytes_taken
        destination += bytes_taken
        bytes_left -= bytes_taken
      end

      SecretWiping.wipe(keystream_storage.to_slice)
      SecretWiping.wipe(Bytes.new(permuted.as(UInt8*), 64))
      SecretWiping.wipe(Bytes.new(state.as(UInt8*), 64))
    end

    # Writes into *subkey* (32 bytes) the key HChaCha20 derives from *key*
    # and the 16 bytes of *nonce*.
    def self.derive_subkey(key : Bytes, nonce : Bytes, subkey : Bytes) : Nil
      raise KeySizeMismatch.new("a ChaCha20 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE
      unless nonce.size == SUBKEY_NONCE_BYTESIZE
        raise NonceSizeMismatch.new("HChaCha20 takes #{SUBKEY_NONCE_BYTESIZE} nonce bytes, not #{nonce.size}")
      end
      raise OutputSizeMismatch.new("the subkey is #{KEY_BYTESIZE} bytes") unless subkey.size == KEY_BYTESIZE

      state_storage = uninitialized UInt32[16]
      state = state_storage.to_unsafe
      state[0] = CONSTANT_WORD_0
      state[1] = CONSTANT_WORD_1
      state[2] = CONSTANT_WORD_2
      state[3] = CONSTANT_WORD_3
      8.times { |index| state[4 + index] = load_word(key.to_unsafe + index * 4) }
      4.times { |index| state[12 + index] = load_word(nonce.to_unsafe + index * 4) }

      permuted_storage = uninitialized UInt32[16]
      permuted = permuted_storage.to_unsafe
      run_twenty_rounds(state, permuted)
      destination = subkey.to_unsafe
      4.times do |index|
        store_word(destination + index * 4, permuted[index])
        store_word(destination + 16 + index * 4, permuted[12 + index])
      end

      SecretWiping.wipe(Bytes.new(permuted.as(UInt8*), 64))
      SecretWiping.wipe(Bytes.new(state.as(UInt8*), 64))
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
  end
end
