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

    # Bytes in the widest group of blocks the assembly makes in one pass: 64
    # times `CHACHA20_BLOCKS_PER_GROUP` of the instruction module, written
    # out as a number because it sizes the staging buffers. On x86-64 the
    # widest pass this processor has is chosen at run time
    # (`widest_group_bytesize`), and this is the widest of all, the
    # AVX-512 pass.
    {% if flag?(:aarch64) %}
      GROUP_BYTESIZE = 576
    {% elsif flag?(:x86_64) %}
      GROUP_BYTESIZE = 1024

      # Bytes in one pass of the SSE, AVX2 and AVX-512 assembly, and in the
      # scratch buffer of the AVX2 pass.
      private SSE_GROUP_BYTESIZE    =  192
      private AVX2_GROUP_BYTESIZE   =  512
      private AVX512_GROUP_BYTESIZE = 1024
      private AVX2_SCRATCH_BYTESIZE =  256

      # The parameter block of the absorbing AVX2 pass, in 64-bit words:
      # 256 bytes of scratch, the ChaCha20 state from word 32, the Poly1305
      # state of `Poly1305WithWideMultiplication` (accumulator, r) and s1
      # from word 40, the input and output addresses at words 46 and 47,
      # and at word 48 the address of the stretch the AVX-512 pass that
      # shares Poly1305 absorbs.
      private ABSORBING_PARAMETER_WORD_COUNT = 49
      private ABSORBING_STATE_WORD           = 32
      private ABSORBING_POLY1305_WORD        = 40
      private ABSORBING_INPUT_WORD           = 46
      private SHARED_STRETCH_WORD            = 48
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

    # Message bytes the first group carries after block 0, at most.
    FIRST_GROUP_MESSAGE_BYTESIZE = GROUP_BYTESIZE - BLOCK_BYTESIZE

    # The widest pass the assembly makes on this processor, in bytes.
    def self.widest_group_bytesize : Int32
      {% if flag?(:x86_64) %}
        return AVX512_GROUP_BYTESIZE if ProcessorFeatures::HAS_AVX512
        return AVX2_GROUP_BYTESIZE if ProcessorFeatures::HAS_AVX2
        SSE_GROUP_BYTESIZE
      {% else %}
        GROUP_BYTESIZE
      {% end %}
    end

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

      {% if flag?(:x86_64) %}
        if shares_poly1305_while_it_ciphers? && plaintext.size >= AVX512_GROUP_BYTESIZE * 2
          seal_sharing_poly1305(key, nonce, associated_data, plaintext, ciphertext, full_tag)
          return
        end
        if absorbs_while_it_ciphers? && plaintext.size >= first_group_message_bytesize + widest_group_bytesize
          seal_absorbing(key, nonce, associated_data, plaintext, ciphertext, full_tag)
          return
        end
        if plaintext.size >= first_group_message_bytesize && widest_group_bytesize > SSE_GROUP_BYTESIZE
          seal_from_a_direct_first_group(key, nonce, associated_data, plaintext, ciphertext, full_tag)
          return
        end
      {% end %}

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
    # and returns true; otherwise returns false without writing *plaintext*
    # (`AuthenticatedEncryption#decrypt` then zeroes it, as for every cipher).
    def self.open(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      raise OutputSizeMismatch.new("the plaintext is as long as the ciphertext") unless plaintext.size == ciphertext.size
      ensure_message_fits(1_u32, ciphertext.size)

      {% if flag?(:aarch64) %}
        return open_absorbing(key, nonce, associated_data, ciphertext, tag, plaintext)
      {% elsif flag?(:x86_64) %}
        if absorbs_while_it_ciphers? && ciphertext.size >= widest_group_bytesize
          return open_absorbing_on_vector_registers(key, nonce, associated_data, ciphertext, tag, plaintext)
        end
        if ProcessorFeatures::HAS_AVX512 && ciphertext.size >= first_group_message_bytesize
          return open_from_a_held_first_group(key, nonce, associated_data, ciphertext, tag, plaintext)
        end
        if ciphertext.size >= widest_group_bytesize && widest_group_bytesize > SSE_GROUP_BYTESIZE
          return open_after_a_separate_key_block(key, nonce, associated_data, ciphertext, tag, plaintext)
        end
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

    {% if flag?(:x86_64) %}
      # Sealing a message that fills the first group of the widest pass: the
      # pass writes block 0's keystream, the Poly1305 key, into a block on
      # the stack and XORs blocks 1 on straight into *ciphertext*, so the
      # message never goes through a staging buffer.
      private def self.seal_from_a_direct_first_group(key : Bytes, nonce : Bytes, associated_data : Bytes, plaintext : Bytes,
                                                      ciphertext : Bytes, full_tag : Bytes) : Nil
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_block_storage = uninitialized UInt8[64]
        first_bytesize = first_group_message_bytesize
        xor_first_group(state, plaintext.to_unsafe, ciphertext.to_unsafe, key_block_storage.to_unsafe)
        xor_from_state(state, plaintext[first_bytesize..], ciphertext[first_bytesize..])
        authenticate(key_block_storage.to_slice[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
        SecretWiping.wipe(key_block_storage.to_slice)
        SecretWiping.wipe(state.to_unsafe_bytes)
      end

      # Whether ChaCha20-Poly1305 runs Poly1305 on the general registers
      # inside the AVX2 keystream passes (`xor_chacha20_keystream_absorbing_poly1305`)
      # rather than as a pass of its own: on processors with AVX2 but not
      # AVX-512, such as Zen 3, whose vector and general units work side by
      # side, so the absorbing costs next to nothing. The pass needs the
      # general multiply of 64 by 64 bits only, which every x86-64 has.
      def self.absorbs_while_it_ciphers? : Bool
        ProcessorFeatures::HAS_AVX2 && !ProcessorFeatures::HAS_AVX512
      end

      # Whether sealing on AVX-512 shares Poly1305 between the general
      # registers, inside the keystream passes, and IFMA after them
      # (`xor_chacha20_keystream_sharing_poly1305`): measured 6 to 21%
      # faster from 4 KiB on the Xeon 6975P-C, EPYC 9V74 and 9V45, whose
      # general multiplier is otherwise idle while the vector units cipher.
      # Opening keeps separate passes, since sharing would hold the whole
      # plaintext in a scratch buffer until the tag is checked, which cost
      # more than it saved.
      def self.shares_poly1305_while_it_ciphers? : Bool
        ProcessorFeatures::HAS_AVX512_INTEGER_FUSED_MULTIPLY_ADD
      end

      # Poly1305 blocks each AVX-512 pass absorbs on the general registers
      # when Poly1305 is shared, of the 64 the pass ciphers: the fastest of
      # 16 to 56 on all three processors.
      private SHARED_BLOCKS_PER_PASS = 40

      # Sealing on AVX-512 with Poly1305 shared (*plaintext* at least two
      # groups): the first group goes straight into *ciphertext*, then each
      # pass absorbs `SHARED_BLOCKS_PER_PASS` blocks of the ciphertext from its
      # start, and IFMA absorbs the rest afterwards.
      private def self.seal_sharing_poly1305(key : Bytes, nonce : Bytes, associated_data : Bytes, plaintext : Bytes,
                                             ciphertext : Bytes, full_tag : Bytes) : Nil
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_block_storage = uninitialized UInt8[64]
        one_time_key = key_block_storage.to_slice[0, POLY1305_KEY_BYTESIZE]
        first_bytesize = AVX512_GROUP_BYTESIZE
        xor_first_group(state, plaintext.to_unsafe, ciphertext.to_unsafe, key_block_storage.to_unsafe)

        parameters_storage = uninitialized UInt64[ABSORBING_PARAMETER_WORD_COUNT]
        parameters = parameters_storage.to_unsafe
        poly1305_state = parameters + ABSORBING_POLY1305_WORD
        Poly1305WithWideMultiplication.start(one_time_key, poly1305_state)
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, associated_data)
        group_count = (plaintext.size - first_bytesize) // AVX512_GROUP_BYTESIZE
        shared = run_sharing_groups(state, parameters, plaintext.to_unsafe + first_bytesize,
          ciphertext.to_unsafe + first_bytesize, ciphertext.to_unsafe, group_count)

        done = first_bytesize + group_count * AVX512_GROUP_BYTESIZE
        xor_from_state(state, plaintext[done..], ciphertext[done..])
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[shared..])
        Poly1305WithWideMultiplication.finish_encrypted_message(poly1305_state, one_time_key, associated_data.size,
          ciphertext.size, full_tag)
        SecretWiping.wipe(Bytes.new(parameters.as(UInt8*), ABSORBING_PARAMETER_WORD_COUNT * 8))
        SecretWiping.wipe(key_block_storage.to_slice)
        SecretWiping.wipe(state.to_unsafe_bytes)
      end

      # Runs *group_count* (at least 1) AVX-512 passes that share Poly1305
      # from *input* to *output*, absorbing from *stretch* into the state
      # at `ABSORBING_POLY1305_WORD` of *parameters*; leaves *state* at the
      # next block and returns the bytes of the stretch absorbed.
      @[NoInline]
      private def self.run_sharing_groups(state : Slice(UInt32), parameters : Pointer(UInt64), input : Pointer(UInt8),
                                          output : Pointer(UInt8), stretch : Pointer(UInt8), group_count : Int32) : Int32
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT
        raise OutputSizeMismatch.new("the sharing pass runs at least once") unless group_count >= 1
        raise UnsupportedProcessor.new("this processor has no AVX-512") unless ProcessorFeatures::HAS_AVX512

        state_words = (parameters + ABSORBING_STATE_WORD).as(UInt32*)
        16.times { |index| state_words[index] = state[index] }
        r1 = parameters[ABSORBING_POLY1305_WORD + 4]
        parameters[ABSORBING_POLY1305_WORD + 5] = r1 &+ r1.unsafe_shr(2)
        parameters[ABSORBING_INPUT_WORD] = input.address
        parameters[ABSORBING_INPUT_WORD + 1] = output.address
        parameters[SHARED_STRETCH_WORD] = stretch.address
        X8664CipherInstructions.xor_chacha20_keystream_sharing_poly1305(parameters, group_count.to_u64, 40)
        state[12] = state_words[12]
        group_count * SHARED_BLOCKS_PER_PASS * 16
      end

      # Sealing on the absorbing pass (*plaintext* at least two groups less
      # 64 bytes): the first group goes straight into *ciphertext* (all but
      # the key block), then each pass absorbs as many bytes of ciphertext,
      # ending 64 bytes into what it writes, and what is left is absorbed
      # afterwards.
      private def self.seal_absorbing(key : Bytes, nonce : Bytes, associated_data : Bytes, plaintext : Bytes,
                                      ciphertext : Bytes, full_tag : Bytes) : Nil
        group_bytesize = widest_group_bytesize
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_block_storage = uninitialized UInt8[64]
        one_time_key = key_block_storage.to_slice[0, POLY1305_KEY_BYTESIZE]
        first_bytesize = first_group_message_bytesize
        xor_first_group(state, plaintext.to_unsafe, ciphertext.to_unsafe, key_block_storage.to_unsafe)

        parameters_storage = uninitialized UInt64[ABSORBING_PARAMETER_WORD_COUNT]
        parameters = parameters_storage.to_unsafe
        poly1305_state = parameters + ABSORBING_POLY1305_WORD
        Poly1305WithWideMultiplication.start(one_time_key, poly1305_state)
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, associated_data)
        group_count = (plaintext.size - first_bytesize) // group_bytesize
        run_absorbing_groups(state, parameters, plaintext.to_unsafe + first_bytesize, ciphertext.to_unsafe + first_bytesize, group_count, true)

        absorbed = group_count * group_bytesize
        done = first_bytesize + absorbed
        left_over = plaintext.size - done
        if !ProcessorFeatures::HAS_AVX512 && 0 < left_over <= SSE_GROUP_BYTESIZE
          seal_last_bytes_absorbing(parameters, plaintext[done..], ciphertext[done..], ciphertext.to_unsafe + absorbed)
          Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[done..])
        else
          xor_from_state(state, plaintext[done..], ciphertext[done..])
          Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[absorbed..])
        end
        Poly1305WithWideMultiplication.finish_encrypted_message(poly1305_state, one_time_key, associated_data.size,
          ciphertext.size, full_tag)
        SecretWiping.wipe(Bytes.new(parameters.as(UInt8*), ABSORBING_PARAMETER_WORD_COUNT * 8))
        SecretWiping.wipe(key_block_storage.to_slice)
        SecretWiping.wipe(state.to_unsafe_bytes)
      end

      # The last pass of a seal on AVX2 when at most one SSE group of
      # *plaintext* is left: the SSE pass that ciphers it absorbs the 448
      # bytes of ciphertext at *pending* (written, not yet absorbed) on the
      # general registers, from the parameter block the absorbing passes
      # left. The bytes go through a staging group.
      private def self.seal_last_bytes_absorbing(parameters : Pointer(UInt64), plaintext : Bytes, ciphertext : Bytes,
                                                 pending : Pointer(UInt8)) : Nil
        staging_storage = StaticArray(UInt8, SSE_GROUP_BYTESIZE).new(0_u8)
        staging = staging_storage.to_slice
        plaintext.copy_to(staging)
        parameters[ABSORBING_INPUT_WORD] = staging.to_unsafe.address
        parameters[ABSORBING_INPUT_WORD + 1] = staging.to_unsafe.address
        X8664CipherInstructions.xor_chacha20_keystream_absorbing_poly1305_on_128_bit_registers(parameters, pending, 28)
        staging[0, plaintext.size].copy_to(ciphertext)
        SecretWiping.wipe(staging)
      end

      # Opening on the absorbing pass (*ciphertext* at least one group): one
      # SSE pass gives the key block, then the whole groups are
      # decrypted into a scratch buffer while their ciphertext is absorbed,
      # and the plaintext leaves the scratch buffer only once the tag is
      # right.
      private def self.open_absorbing_on_vector_registers(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes,
                                                          tag : Bytes, plaintext : Bytes) : Bool
        group_bytesize = widest_group_bytesize
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_staging_storage = StaticArray(UInt8, SSE_GROUP_BYTESIZE).new(0_u8)
        key_staging = key_staging_storage.to_slice
        xor_groups_of(SSE_GROUP_BYTESIZE, state, key_staging.to_unsafe, key_staging.to_unsafe, 1_u64)
        state[12] = 1_u32
        one_time_key = key_staging[0, POLY1305_KEY_BYTESIZE]

        parameters_storage = uninitialized UInt64[ABSORBING_PARAMETER_WORD_COUNT]
        parameters = parameters_storage.to_unsafe
        poly1305_state = parameters + ABSORBING_POLY1305_WORD
        Poly1305WithWideMultiplication.start(one_time_key, poly1305_state)
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, associated_data)
        group_count = ciphertext.size // group_bytesize
        absorbed = group_count * group_bytesize
        stack_scratch_storage = uninitialized UInt8[STACK_SCRATCH_BYTESIZE]
        if absorbed <= STACK_SCRATCH_BYTESIZE
          scratch = stack_scratch_storage.to_slice[0, absorbed]
        else
          scratch = Bytes.new(GC.malloc_atomic(absorbed.to_u64).as(UInt8*), absorbed)
        end
        run_absorbing_groups(state, parameters, ciphertext.to_unsafe, scratch.to_unsafe, group_count, false)
        Poly1305WithWideMultiplication.absorb_padded(poly1305_state, ciphertext[absorbed..])

        full_tag_storage = uninitialized UInt8[16]
        full_tag = full_tag_storage.to_slice
        Poly1305WithWideMultiplication.finish_encrypted_message(poly1305_state, one_time_key, associated_data.size,
          ciphertext.size, full_tag)
        tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
        SecretWiping.wipe(full_tag)
        is_authentic = Declassification.reveal(tags_match)
        if is_authentic
          scratch.copy_to(plaintext)
          xor_from_state(state, ciphertext[absorbed..], plaintext[absorbed..])
        end
        SecretWiping.wipe(scratch)
        GC.free(scratch.to_unsafe.as(Void*)) if absorbed > STACK_SCRATCH_BYTESIZE
        SecretWiping.wipe(Bytes.new(parameters.as(UInt8*), ABSORBING_PARAMETER_WORD_COUNT * 8))
        SecretWiping.wipe(key_staging)
        SecretWiping.wipe(state.to_unsafe_bytes)
        is_authentic
      end

      # *group_count* (at least 1) passes of the absorbing assembly from the
      # counter in *state*, with the Poly1305 state at
      # `ABSORBING_POLY1305_WORD` of *parameters*; leaves *state* at the
      # next block.
      @[NoInline]
      private def self.run_absorbing_groups(state : Slice(UInt32), parameters : Pointer(UInt64), input : Pointer(UInt8),
                                            output : Pointer(UInt8), group_count : Int32, is_sealing : Bool) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT
        raise OutputSizeMismatch.new("the absorbing pass runs at least once") unless group_count >= 1

        state_words = (parameters + ABSORBING_STATE_WORD).as(UInt32*)
        16.times { |index| state_words[index] = state[index] }
        r1 = parameters[ABSORBING_POLY1305_WORD + 4]
        parameters[ABSORBING_POLY1305_WORD + 5] = r1 &+ r1.unsafe_shr(2)
        parameters[ABSORBING_INPUT_WORD] = input.address
        parameters[ABSORBING_INPUT_WORD + 1] = output.address
        if is_sealing
          X8664CipherInstructions.xor_chacha20_keystream_absorbing_poly1305(parameters, group_count.to_u64, true)
        else
          X8664CipherInstructions.xor_chacha20_keystream_absorbing_poly1305(parameters, group_count.to_u64, false)
        end
        state[12] = state_words[12]
      end

      # Opening on AVX-512 a message that fills the first group: the pass
      # that gives the key block decrypts the first 1024 bytes into a block
      # on the stack, and they reach *plaintext*, with the rest, only once
      # the tag is right.
      private def self.open_from_a_held_first_group(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes,
                                                    tag : Bytes, plaintext : Bytes) : Bool
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_block_storage = uninitialized UInt8[64]
        held_storage = uninitialized UInt8[AVX512_GROUP_BYTESIZE]
        held = held_storage.to_slice
        xor_first_group(state, ciphertext.to_unsafe, held.to_unsafe, key_block_storage.to_unsafe)

        full_tag_storage = uninitialized UInt8[16]
        full_tag = full_tag_storage.to_slice
        authenticate(key_block_storage.to_slice[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
        tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
        SecretWiping.wipe(full_tag)
        SecretWiping.wipe(key_block_storage.to_slice)
        is_authentic = Declassification.reveal(tags_match)
        if is_authentic
          held.copy_to(plaintext)
          xor_from_state(state, ciphertext[AVX512_GROUP_BYTESIZE..], plaintext[AVX512_GROUP_BYTESIZE..])
        end
        SecretWiping.wipe(held)
        SecretWiping.wipe(state.to_unsafe_bytes)
        is_authentic
      end

      # Opening a message of at least one whole group of the widest pass:
      # one SSE pass gives block 0, the Poly1305 key, and once the tag is
      # right the message is decrypted from block 1, whole groups straight
      # from *ciphertext* into *plaintext*.
      private def self.open_after_a_separate_key_block(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes,
                                                       tag : Bytes, plaintext : Bytes) : Bool
        state_storage = uninitialized UInt32[26]
        state = state_storage.to_slice
        load_state(key, nonce, 0_u32, state)
        key_staging_storage = StaticArray(UInt8, SSE_GROUP_BYTESIZE).new(0_u8)
        key_staging = key_staging_storage.to_slice
        xor_groups_of(SSE_GROUP_BYTESIZE, state, key_staging.to_unsafe, key_staging.to_unsafe, 1_u64)
        state[12] = 1_u32

        full_tag_storage = uninitialized UInt8[16]
        full_tag = full_tag_storage.to_slice
        authenticate(key_staging[0, POLY1305_KEY_BYTESIZE], associated_data, ciphertext, full_tag)
        tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
        SecretWiping.wipe(full_tag)
        SecretWiping.wipe(key_staging)
        is_authentic = Declassification.reveal(tags_match)
        xor_from_state(state, ciphertext, plaintext) if is_authentic
        SecretWiping.wipe(state.to_unsafe_bytes)
        is_authentic
      end

      # Message bytes `xor_first_group` XORs: the AVX-512 pass carries a
      # seventeenth block in its first group, so it fills 1024 bytes after
      # the key block; the AVX2 pass fills 448.
      private def self.first_group_message_bytesize : Int32
        return AVX512_GROUP_BYTESIZE if ProcessorFeatures::HAS_AVX512
        AVX2_GROUP_BYTESIZE - BLOCK_BYTESIZE
      end

      # One pass of the widest assembly from block 0 of *state*: block 0's
      # keystream goes to *key_block* (64 bytes), the others XOR the
      # `first_group_message_bytesize` bytes at *input* into *output*.
      @[NoInline]
      private def self.xor_first_group(state : Slice(UInt32), input : Pointer(UInt8), output : Pointer(UInt8), key_block : Pointer(UInt8)) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

        state_pointer = state.to_unsafe
        if ProcessorFeatures::HAS_AVX512
          X8664CipherInstructions.xor_chacha20_keystream_on_512_bit_registers(state_pointer, input, output, 1_u64, key_block)
        else
          raise UnsupportedProcessor.new("this processor has no AVX2") unless ProcessorFeatures::HAS_AVX2
          scratch_storage = uninitialized UInt8[AVX2_SCRATCH_BYTESIZE]
          scratch_pointer = scratch_storage.to_unsafe
          X8664CipherInstructions.xor_chacha20_keystream_on_256_bit_registers(state_pointer, scratch_pointer, input, output, 1_u64, key_block)
          SecretWiping.wipe(scratch_storage.to_slice)
        end
      end
    {% end %}

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
      first_bytesize = Math.min(message.size, widest_group_bytesize - BLOCK_BYTESIZE)
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
    # blocks when they go on the general registers, else a whole group (on
    # x86-64, of the narrowest pass that covers them).
    private def self.staging_bytesize_for(bytesize : Int32) : Int32
      {% if flag?(:aarch64) %}
        block_count = (bytesize + BLOCK_BYTESIZE - 1) // BLOCK_BYTESIZE
        return block_count * BLOCK_BYTESIZE if block_count <= MOST_GENERAL_REGISTER_BLOCKS
      {% elsif flag?(:x86_64) %}
        return SSE_GROUP_BYTESIZE if bytesize <= SSE_GROUP_BYTESIZE
        return AVX2_GROUP_BYTESIZE if bytesize <= AVX2_GROUP_BYTESIZE && ProcessorFeatures::HAS_AVX2
        return widest_group_bytesize
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
      {% if flag?(:x86_64) %}
        xor_groups_of(staging.size, state, staging.to_unsafe, staging.to_unsafe, 1_u64)
      {% else %}
        xor_groups(state, staging.to_unsafe, staging.to_unsafe, 1_u64)
      {% end %}
    end

    # XORs the keystream from the counter in *state* into *input*: whole
    # groups in place, then the bytes left over through a staging buffer.
    private def self.xor_from_state(state : Slice(UInt32), input : Bytes, output : Bytes) : Nil
      group_bytesize = widest_group_bytesize
      group_count = input.size // group_bytesize
      xor_groups(state, input.to_unsafe, output.to_unsafe, group_count.to_u64) if group_count > 0
      done = group_count * group_bytesize
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
        xor_groups_of(widest_group_bytesize, state, input, output, group_count)
      {% else %}
        raise UnsupportedProcessor.new("this processor has no vector instructions Beryl can use")
      {% end %}
    end

    {% if flag?(:x86_64) %}
      # *group_count* passes of the assembly whose pass is *group_bytesize*
      # bytes: AVX-512, AVX2 or SSE. The AVX2 pass keeps four words of the
      # state in a scratch buffer on the stack, wiped afterwards.
      @[NoInline]
      private def self.xor_groups_of(group_bytesize : Int32, state : Slice(UInt32), input : Pointer(UInt8), output : Pointer(UInt8),
                                     group_count : UInt64) : Nil
        raise OutputSizeMismatch.new("the working state is #{STATE_WORD_COUNT} words") unless state.size == STATE_WORD_COUNT

        state_pointer = state.to_unsafe
        case group_bytesize
        when AVX512_GROUP_BYTESIZE
          raise UnsupportedProcessor.new("this processor has no AVX-512") unless ProcessorFeatures::HAS_AVX512
          X8664CipherInstructions.xor_chacha20_keystream_on_512_bit_registers(state_pointer, input, output, group_count)
        when AVX2_GROUP_BYTESIZE
          raise UnsupportedProcessor.new("this processor has no AVX2") unless ProcessorFeatures::HAS_AVX2
          scratch_storage = uninitialized UInt8[AVX2_SCRATCH_BYTESIZE]
          scratch_pointer = scratch_storage.to_unsafe
          X8664CipherInstructions.xor_chacha20_keystream_on_256_bit_registers(state_pointer, scratch_pointer, input, output, group_count)
          SecretWiping.wipe(scratch_storage.to_slice)
        else
          X8664CipherInstructions.xor_chacha20_keystream(state_pointer, input, output, group_count)
        end
      end
    {% end %}

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
