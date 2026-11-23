require "crypto/subtle"
require "../armv8_cipher_instructions"
require "../declassification"
require "../error"
require "../processor_features"
require "../secret_wiping"
require "../x86_64_cipher_instructions"
require "./chacha20_stream_cipher"
require "./poly1305_one_time_authenticator"
require "./poly1305_with_wide_multiplication"

module Amber::Beryl::Crypto::V1
  # :nodoc:
  #
  # ChaCha20 and ChaCha20-Poly1305 (RFC 8439) on the processor's vector
  # instructions: the assembly in `Armv8CipherInstructions` or
  # `X8664CipherInstructions` makes the keystream a group of blocks at a
  # time, and this module handles the state, the first group and the bytes
  # left after the last whole group.
  #
  # The first group of a message starts at block 0, whose first 32 bytes are
  # the Poly1305 key; the message's first bytes ride in the same group from
  # block 1. Sealing a short message, or opening one, therefore runs the
  # keystream once. A group that the message only partly fills runs on a
  # copy in a staging buffer, which is wiped afterwards.
  #
  # Every buffer is treated as secret. Sizes and the block counter are
  # public.
  module ChaCha20WithVectorInstructions
    BLOCK_BYTESIZE = 64

    # Bytes in one group of blocks the assembly makes in one pass: 64 times
    # `CHACHA20_BLOCKS_PER_GROUP` of the instruction module, written out as
    # a number because it sizes the staging buffers.
    {% if flag?(:aarch64) %}
      GROUP_BYTESIZE = 576
    {% elsif flag?(:x86_64) %}
      GROUP_BYTESIZE = 192
    {% else %}
      GROUP_BYTESIZE = 64
    {% end %}

    # Words of working state: the sixteen of ChaCha20, then two words of
    # padding and the Poly1305 state of `Poly1305WithWideMultiplication`
    # from byte 64, which the AArch64 assembly reads and writes there.
    private STATE_WORD_COUNT    = 26
    private POLY1305_STATE_WORD =  8

    # Most blocks run one after the other on the general registers in
    # place of a vector group.
    private MOST_GENERAL_REGISTER_BLOCKS = 2

    # The longest rest of a message the AArch64 opening decrypts into a
    # scratch buffer on the stack; a longer one gets one from the heap.
    private STACK_SCRATCH_BYTESIZE = 4096

    # Bytes in one group of the AArch64 pass that also absorbs Poly1305:
    # seven blocks, the eighth's general registers going to Poly1305.
    ABSORBING_GROUP_BYTESIZE = 448

    # Message bytes the first group carries after block 0.
    FIRST_GROUP_MESSAGE_BYTESIZE = GROUP_BYTESIZE - BLOCK_BYTESIZE

    private POLY1305_KEY_BYTESIZE = 32

    # XORs *input* into *output* with the keystream of *key* and *nonce*,
    # starting at block number *initial_counter*.
    def self.xor_keystream(key : Bytes, nonce : Bytes, initial_counter : UInt32, input : Bytes, output : Bytes) : Nil
      raise OutputSizeMismatch.new("a stream cipher writes as many bytes as it reads") unless input.size == output.size
      ensure_message_fits(initial_counter, input.size)

      state_storage = uninitialized UInt32[26]
      state = state_storage.to_slice
      load_state(key, nonce, initial_counter, state)
      xor_from_state(state, input, output)
      SecretWiping.wipe(state_storage.to_slice.to_unsafe_bytes)
    end

    # ChaCha20-Poly1305 sealing (RFC 8439 §2.8): encrypts *plaintext* into
    # *ciphertext* from block 1 and writes the full tag into *full_tag*.
    def self.seal(key : Bytes, nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      raise OutputSizeMismatch.new("the ciphertext is as long as the plaintext") unless plaintext.size == ciphertext.size
      ensure_message_fits(1_u32, plaintext.size)

      with_first_group(key, nonce, plaintext) do |state, staging, first_bytesize|
        staging[BLOCK_BYTESIZE, first_bytesize].copy_to(ciphertext)
        {% if flag?(:aarch64) %}
          one_time_key = staging[0, POLY1305_KEY_BYTESIZE]
          poly1305_state = state.to_unsafe.as(UInt64*) + POLY1305_STATE_WORD
          Poly1305WithWideMultiplication.start(one_time_key, poly1305_state)
          Poly1305WithWideMultiplication.absorb_padded(poly1305_state, associated_data)
          rest_bytesize = plaintext.size - first_bytesize
          if rest_bytesize >= ABSORBING_GROUP_BYTESIZE
            # Absorbing group k absorbs ciphertext bytes from 448 * k on,
            # which the first group and the groups before k have written.
            group_count = rest_bytesize // ABSORBING_GROUP_BYTESIZE
            xor_groups_absorbing(state, plaintext.to_unsafe + first_bytesize, ciphertext.to_unsafe + first_bytesize,
              group_count.to_u64, ciphertext.to_unsafe)
            absorbed = group_count * ABSORBING_GROUP_BYTESIZE
            done = first_bytesize + absorbed
            xor_from_state(state, plaintext[done..], ciphertext[done..])
            Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[absorbed..])
          else
            xor_from_state(state, plaintext[first_bytesize..], ciphertext[first_bytesize..])
            Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext)
          end
          Poly1305WithWideMultiplication.finish_encrypted_message(poly1305_state, one_time_key, associated_data.size,
            ciphertext.size, full_tag)
        {% else %}
          xor_from_state(state, plaintext[first_bytesize..], ciphertext[first_bytesize..])
          authenticate(staging[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
        {% end %}
      end
    end

    # ChaCha20-Poly1305 opening: when *tag* is the first `tag.size` bytes of
    # the right tag, writes the plaintext of *ciphertext* into *plaintext*
    # and returns true; otherwise returns false and leaves *plaintext*
    # untouched.
    def self.open(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      raise OutputSizeMismatch.new("the plaintext is as long as the ciphertext") unless plaintext.size == ciphertext.size
      ensure_message_fits(1_u32, ciphertext.size)

      {% if flag?(:aarch64) %}
        return open_absorbing(key, nonce, associated_data, ciphertext, tag, plaintext)
      {% end %}

      is_authentic = false
      with_first_group(key, nonce, ciphertext) do |state, staging, first_bytesize|
        full_tag_storage = uninitialized UInt8[16]
        full_tag = full_tag_storage.to_slice
        authenticate(staging[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
        tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
        SecretWiping.wipe(full_tag)
        is_authentic = Declassification.reveal(tags_match)
        if is_authentic
          staging[BLOCK_BYTESIZE, first_bytesize].copy_to(plaintext)
          xor_from_state(state, ciphertext[first_bytesize..], plaintext[first_bytesize..])
        end
      end
      is_authentic
    end

    # Opening on AArch64: one pass absorbs the ciphertext into Poly1305
    # while it decrypts into a scratch buffer, and the plaintext leaves the
    # scratch buffer only once the tag is right.
    private def self.open_absorbing(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      is_authentic = false
      with_first_group(key, nonce, ciphertext) do |state, staging, first_bytesize|
        one_time_key = staging[0, POLY1305_KEY_BYTESIZE]
        poly1305_state = state.to_unsafe.as(UInt64*) + POLY1305_STATE_WORD
        Poly1305WithWideMultiplication.start(one_time_key, poly1305_state)
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, associated_data)
        rest_bytesize = ciphertext.size - first_bytesize
        rest = ciphertext[first_bytesize..]
        group_count = rest_bytesize // ABSORBING_GROUP_BYTESIZE
        stack_scratch_storage = uninitialized UInt8[STACK_SCRATCH_BYTESIZE]
        scratch = Bytes.empty
        if group_count > 0
          if rest_bytesize <= STACK_SCRATCH_BYTESIZE
            scratch = stack_scratch_storage.to_slice[0, rest_bytesize]
          else
            scratch = Bytes.new(GC.malloc_atomic(rest_bytesize.to_u64).as(UInt8*), rest_bytesize)
          end
          # Absorbing group k absorbs ciphertext from 448 * k on while it
          # decrypts the bytes after the first group into the scratch buffer.
          xor_groups_absorbing(state, rest.to_unsafe, scratch.to_unsafe, group_count.to_u64, ciphertext.to_unsafe)
          absorbed = group_count * ABSORBING_GROUP_BYTESIZE
          xor_from_state(state, rest[absorbed..], scratch[absorbed..])
          Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[absorbed..])
        else
          Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext)
        end

        full_tag_storage = uninitialized UInt8[16]
        full_tag = full_tag_storage.to_slice
        Poly1305WithWideMultiplication.finish_encrypted_message(poly1305_state, one_time_key, associated_data.size,
          ciphertext.size, full_tag)
        tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
        SecretWiping.wipe(full_tag)
        is_authentic = Declassification.reveal(tags_match)
        if is_authentic
          staging[BLOCK_BYTESIZE, first_bytesize].copy_to(plaintext)
          if scratch.empty?
            xor_from_state(state, rest, plaintext[first_bytesize..])
          else
            scratch.copy_to(plaintext[first_bytesize..])
          end
        end
        unless scratch.empty?
          SecretWiping.wipe(scratch)
          GC.free(scratch.to_unsafe.as(Void*)) if rest_bytesize > STACK_SCRATCH_BYTESIZE
        end
      end
      is_authentic
    end

    # Writes into *full_tag* the ChaCha20-Poly1305 tag of *ciphertext* and
    # *associated_data*.
    def self.write_tag(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      with_first_group(key, nonce, Bytes.empty) do |_state, staging, _first_bytesize|
        authenticate(staging[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
      end
    end

    # The Poly1305 tag RFC 8439 §2.8 defines, on the wide multiply where the
    # processor has it.
    def self.authenticate(one_time_key : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      if ProcessorFeatures::HAS_WIDE_MULTIPLICATION
        Poly1305WithWideMultiplication.authenticate_encrypted_message(one_time_key, associated_data, ciphertext, full_tag)
      else
        Poly1305OneTimeAuthenticator.authenticate_encrypted_message(one_time_key, associated_data, ciphertext, full_tag)
      end
    end

    # Runs the first group of *message* (counter 0) in a staging buffer that
    # holds a zero block, then up to `FIRST_GROUP_MESSAGE_BYTESIZE` bytes of
    # *message*; yields the state, left at the next group, the staging
    # buffer, which now holds block 0's keystream and those bytes XORed with
    # theirs, and how many message bytes it carries. Wipes both afterwards.
    private def self.with_first_group(key : Bytes, nonce : Bytes, message : Bytes, & : Slice(UInt32), Bytes, Int32 -> Nil) : Nil
      state_storage = uninitialized UInt32[26]
      state = state_storage.to_slice
      load_state(key, nonce, 0_u32, state)
      staging_storage = uninitialized UInt8[GROUP_BYTESIZE]
      first_bytesize = Math.min(message.size, FIRST_GROUP_MESSAGE_BYTESIZE)
      # Only the blocks the keystream runs over are used, so only they are
      # cleared before and wiped after.
      used_bytesize = staging_bytesize_for(BLOCK_BYTESIZE + first_bytesize)
      staging = staging_storage.to_slice[0, used_bytesize]
      staging.fill(0_u8)
      message[0, first_bytesize].copy_to(staging[BLOCK_BYTESIZE, first_bytesize])
      xor_blocks_or_group(state, staging, BLOCK_BYTESIZE + first_bytesize)

      yield state, staging, first_bytesize

      SecretWiping.wipe(staging)
      SecretWiping.wipe(state.to_unsafe_bytes)
    end

    # The staging bytes the keystream of *bytesize* bytes runs over: whole
    # blocks when they go on the general registers, else a whole group.
    private def self.staging_bytesize_for(bytesize : Int32) : Int32
      {% if flag?(:aarch64) %}
        block_count = (bytesize + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE
        return block_count * BLOCK_BYTESIZE if block_count <= MOST_GENERAL_REGISTER_BLOCKS
      {% end %}
      GROUP_BYTESIZE
    end

    # XORs the keystream into the first *bytesize* bytes of *staging*
    # (rounded up to whole blocks): one block at a time on the general
    # registers when there are at most `MOST_GENERAL_REGISTER_BLOCKS`
    # blocks, which takes less time than a vector group, else one group.
    private def self.xor_blocks_or_group(state : Slice(UInt32), staging : Bytes, bytesize : Int32) : Nil
      {% if flag?(:aarch64) %}
        block_count = (bytesize + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE
        if block_count <= MOST_GENERAL_REGISTER_BLOCKS
          xor_blocks_on_general_registers(state, staging.to_unsafe, block_count.to_u64)
          return
        end
      {% end %}
      xor_groups(state, staging.to_unsafe, staging.to_unsafe, 1_u64)
    end

    # XORs the keystream from the counter in *state* into *input*: whole
    # groups in place, then the bytes left over through a staging buffer.
    private def self.xor_from_state(state : Slice(UInt32), input : Bytes, output : Bytes) : Nil
      group_count = input.size // GROUP_BYTESIZE
      xor_groups(state, input.to_unsafe, output.to_unsafe, group_count.to_u64) if group_count > 0
      done = group_count * GROUP_BYTESIZE
      left_over = input.size - done
      return if left_over == 0

      staging_storage = uninitialized UInt8[GROUP_BYTESIZE]
      staging = staging_storage.to_slice[0, staging_bytesize_for(left_over)]
      staging.fill(0_u8)
      input[done, left_over].copy_to(staging)
      xor_blocks_or_group(state, staging, left_over)
      staging[0, left_over].copy_to(output[done, left_over])
      SecretWiping.wipe(staging)
    end

    # ChaCha20 counts blocks in 32 bits, so a message starting at block
    # *initial_counter* holds at most 2^32 - *initial_counter* blocks.
    private def self.ensure_message_fits(initial_counter : UInt32, message_bytesize : Int32) : Nil
      blocks_available = (1_u64 << 32) - initial_counter
      return if message_bytesize.to_u64 <= blocks_available * BLOCK_BYTESIZE

      raise MessageTooLong.new("ChaCha20 counts #{blocks_available} blocks from block #{initial_counter}, the message needs more")
    end

    private def self.load_state(key : Bytes, nonce : Bytes, initial_counter : UInt32, state : Slice(UInt32)) : Nil
      raise KeySizeMismatch.new("a ChaCha20 key is #{ChaCha20StreamCipher::KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == ChaCha20StreamCipher::KEY_BYTESIZE
      unless nonce.size == ChaCha20StreamCipher::NONCE_BYTESIZE
        raise NonceSizeMismatch.new("a ChaCha20 nonce is #{ChaCha20StreamCipher::NONCE_BYTESIZE} bytes, not #{nonce.size}")
      end

      state[0] = 0x61707865_u32
      state[1] = 0x3320646e_u32
      state[2] = 0x79622d32_u32
      state[3] = 0x6b206574_u32
      # Both processors this module runs on are little-endian, so the words
      # load as they are stored.
      key_words = key.to_unsafe.as(UInt32*)
      8.times { |index| state[4 + index] = key_words[index] }
      state[12] = initial_counter
      nonce_words = nonce.to_unsafe.as(UInt32*)
      3.times { |index| state[13 + index] = nonce_words[index] }
    end

    # The assembly, kept out of line so that the program holds one copy.
    # The callers pass a group count of at least 1.
    @[NoInline]
    private def self.xor_groups(state : Slice(UInt32), input : Pointer(UInt8), output : Pointer(UInt8), group_count : UInt64) : Nil
      raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

      state_pointer = state.to_unsafe
      {% if flag?(:aarch64) %}
        Armv8CipherInstructions.xor_chacha20_keystream(state_pointer, input, output, group_count)
      {% elsif flag?(:x86_64) %}
        X8664CipherInstructions.xor_chacha20_keystream(state_pointer, input, output, group_count)
      {% else %}
        raise UnsupportedProcessor.new("this processor has no vector instructions Beryl can use")
      {% end %}
    end

    {% if flag?(:aarch64) %}
      # The pass that also absorbs into the Poly1305 state at byte 64 of
      # *state* the 28 blocks per group at *poly1305_input*.
      @[NoInline]
      private def self.xor_groups_absorbing(state : Slice(UInt32), input : Pointer(UInt8), output : Pointer(UInt8),
                                            group_count : UInt64, poly1305_input : Pointer(UInt8)) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

        state_pointer = state.to_unsafe
        Armv8CipherInstructions.xor_chacha20_keystream(state_pointer, input, output, group_count, true, poly1305_input)
      end

      @[NoInline]
      private def self.xor_blocks_on_general_registers(state : Slice(UInt32), staging : Pointer(UInt8), block_count : UInt64) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

        state_pointer = state.to_unsafe
        Armv8CipherInstructions.xor_chacha20_keystream_on_general_registers(state_pointer, staging, staging, block_count)
      end

      # Longest message XChaCha20-Poly1305 seals or opens in one statement
      # that derives the subkey and runs blocks 0 and 1.
      LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE = BLOCK_BYTESIZE

      # XChaCha20-Poly1305 for a message of at most
      # `LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE` bytes under *key* and the
      # 24-byte *nonce*: HChaCha20 and the two blocks run in one assembly
      # statement on the general registers, then Poly1305 authenticates.
      # *message* is the plaintext when sealing and the ciphertext when
      # opening; yields the one-time key and the message XORed with the
      # keystream.
      def self.with_short_extended_keystream(key : Bytes, nonce : Bytes, message : Bytes, & : Bytes, Bytes -> Nil) : Nil
        raise KeySizeMismatch.new("a ChaCha20 key is #{ChaCha20StreamCipher::KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == ChaCha20StreamCipher::KEY_BYTESIZE
        raise NonceSizeMismatch.new("an XChaCha20 nonce is 24 bytes, not #{nonce.size}") unless nonce.size == 24
        raise OutputSizeMismatch.new("this path takes at most #{LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE} bytes") if message.size > LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE

        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        state[0] = 0x61707865_u32
        state[1] = 0x3320646e_u32
        state[2] = 0x79622d32_u32
        state[3] = 0x6b206574_u32
        key_words = key.to_unsafe.as(UInt32*)
        8.times { |index| state[4 + index] = key_words[index] }
        nonce_words = nonce.to_unsafe.as(UInt32*)
        6.times { |index| state[12 + index] = nonce_words[index] }
        staging_storage = StaticArray(UInt8, 128).new(0_u8)
        staging = staging_storage.to_slice
        message.copy_to(staging[BLOCK_BYTESIZE, message.size])
        xor_extended_blocks(state, staging.to_unsafe)

        yield staging[0, POLY1305_KEY_BYTESIZE], staging[BLOCK_BYTESIZE, message.size]

        SecretWiping.wipe(staging)
        SecretWiping.wipe(state.to_unsafe_bytes)
      end

      @[NoInline]
      private def self.xor_extended_blocks(state : Slice(UInt32), staging : Pointer(UInt8)) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

        state_pointer = state.to_unsafe
        Armv8CipherInstructions.xor_chacha20_keystream_on_general_registers(state_pointer, staging, staging, 2_u64, false, true)
      end

      # HChaCha20 on the general registers: writes into *subkey* the key
      # XChaCha20 derives from *key* and the first 16 bytes of its nonce.
      def self.derive_subkey(key : Bytes, nonce : Bytes, subkey : Bytes) : Nil
        raise KeySizeMismatch.new("a ChaCha20 key is #{ChaCha20StreamCipher::KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == ChaCha20StreamCipher::KEY_BYTESIZE
        unless nonce.size == ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE
          raise NonceSizeMismatch.new("HChaCha20 takes #{ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE} nonce bytes, not #{nonce.size}")
        end
        raise OutputSizeMismatch.new("the subkey is #{ChaCha20StreamCipher::KEY_BYTESIZE} bytes") unless subkey.size == ChaCha20StreamCipher::KEY_BYTESIZE

        state_storage = uninitialized UInt32[16]
        state = state_storage.to_slice
        state[0] = 0x61707865_u32
        state[1] = 0x3320646e_u32
        state[2] = 0x79622d32_u32
        state[3] = 0x6b206574_u32
        key_words = key.to_unsafe.as(UInt32*)
        8.times { |index| state[4 + index] = key_words[index] }
        nonce_words = nonce.to_unsafe.as(UInt32*)
        4.times { |index| state[12 + index] = nonce_words[index] }
        write_subkey(state.to_unsafe, subkey.to_unsafe)
        SecretWiping.wipe(state.to_unsafe_bytes)
      end

      @[NoInline]
      private def self.write_subkey(state : Pointer(UInt32), subkey : Pointer(UInt8)) : Nil
        Armv8CipherInstructions.xor_chacha20_keystream_on_general_registers(state, subkey, subkey, 1_u64, true)
      end
    {% end %}
  end
end
