require "./block_hash_function"
require "../processor_features"
require "../armv8_hash_instructions"
require "../x86_64_hash_instructions"

module Amber::Beryl::Crypto::V1
  # The SHA-2 compression function on 32-bit words (FIPS 180-4 §6.2), shared
  # by SHA-224 and SHA-256, which differ only in their initial state and in
  # how much of the final state they output.
  abstract class SecureHashWith32BitWords < BlockHashFunction
    # The number of bytes the compression function consumes per step.
    BLOCK_SIZE = 64

    # The sixty-four round constants of FIPS 180-4 §4.2.2.
    ROUND_CONSTANTS = {
      0x428a2f98_u32, 0x71374491_u32, 0xb5c0fbcf_u32, 0xe9b5dba5_u32, 0x3956c25b_u32, 0x59f111f1_u32, 0x923f82a4_u32, 0xab1c5ed5_u32,
      0xd807aa98_u32, 0x12835b01_u32, 0x243185be_u32, 0x550c7dc3_u32, 0x72be5d74_u32, 0x80deb1fe_u32, 0x9bdc06a7_u32, 0xc19bf174_u32,
      0xe49b69c1_u32, 0xefbe4786_u32, 0x0fc19dc6_u32, 0x240ca1cc_u32, 0x2de92c6f_u32, 0x4a7484aa_u32, 0x5cb0a9dc_u32, 0x76f988da_u32,
      0x983e5152_u32, 0xa831c66d_u32, 0xb00327c8_u32, 0xbf597fc7_u32, 0xc6e00bf3_u32, 0xd5a79147_u32, 0x06ca6351_u32, 0x14292967_u32,
      0x27b70a85_u32, 0x2e1b2138_u32, 0x4d2c6dfc_u32, 0x53380d13_u32, 0x650a7354_u32, 0x766a0abb_u32, 0x81c2c92e_u32, 0x92722c85_u32,
      0xa2bfe8a1_u32, 0xa81a664b_u32, 0xc24b8b70_u32, 0xc76c51a3_u32, 0xd192e819_u32, 0xd6990624_u32, 0xf40e3585_u32, 0x106aa070_u32,
      0x19a4c116_u32, 0x1e376c08_u32, 0x2748774c_u32, 0x34b0bcb5_u32, 0x391c0cb3_u32, 0x4ed8aa4a_u32, 0x5b9cca4f_u32, 0x682e6ff3_u32,
      0x748f82ee_u32, 0x78a5636f_u32, 0x84c87814_u32, 0x8cc70208_u32, 0x90befffa_u32, 0xa4506ceb_u32, 0xbef9a3f7_u32, 0xc67178f2_u32,
    }

    @state = uninitialized UInt32[8]

    # Returns the eight initial state words of the concrete hash function.
    abstract def initial_state : StaticArray(UInt32, 8)

    def block_size : Int32
      BLOCK_SIZE
    end

    private def reset_state : Nil
      @state = initial_state
    end

    private def copy_running_state_from(source : self) : Nil
      @state = source.@state
    end

    private def length_field_bytesize : Int32
      8
    end

    private def encode_message_bit_length(message_bytesize : UInt64, length_field : Bytes) : Nil
      IO::ByteFormat::BigEndian.encode(message_bytesize << 3, length_field)
    end

    private def encode_digest(dst : Bytes) : Nil
      (dst.size // 4).times do |word_index|
        IO::ByteFormat::BigEndian.encode(@state[word_index], dst[word_index * 4, 4])
      end
    end

    # Mixes whole blocks into the state: with the processor's SHA-256
    # instructions where it has them (`ProcessorFeatures`), with the portable
    # code below everywhere else. Kept out of line so that the program holds
    # one copy of the assembly and its table of constants per hash.
    @[NoInline]
    private def compress(list_of_blocks : Bytes) : Nil
      {% if flag?(:aarch64) || (flag?(:x86_64) && flag?(:linux)) %}
        if ProcessorFeatures::HAS_SHA256_INSTRUCTIONS
          state_pointer = pointerof(@state).as(UInt32*)
          block_pointer = list_of_blocks.to_unsafe
          block_count = (list_of_blocks.size // BLOCK_SIZE).to_u64
          return if block_count == 0
    
          {% if flag?(:aarch64) %}
            Armv8HashInstructions.compress_sha256_blocks(state_pointer, block_pointer, block_count, ::Beryl::Crypto::V1::SecureHashWith32BitWords::ROUND_CONSTANTS)
          {% else %}
            X8664HashInstructions.compress_sha256_blocks(state_pointer, block_pointer, block_count, ::Beryl::Crypto::V1::SecureHashWith32BitWords::ROUND_CONSTANTS)
          {% end %}
          return
        end
      {% end %}
      compress_with_portable_code(list_of_blocks)
    end

    # One round per constant of FIPS 180-4 §4.2.2. The rounds are written out
    # by the macro below; in round `t` the working variable that the standard
    # calls `a` lives in the local named by `names[(64 - t) % 8]`, so the
    # standard's "shift every variable down one" costs nothing at run time.
    # Ch and Maj are written in their equal forms with fewer operations:
    # Ch(e, f, g) = g ^ (e & (f ^ g)) and Maj(a, b, c) = b ^ ((a ^ b) & (b ^ c)).
    private def compress_with_portable_code(list_of_blocks : Bytes) : Nil
      w = uninitialized UInt32[64]
      # The loop runs once per whole block, so every read below stays
      # inside *list_of_blocks*.
      block_pointer = list_of_blocks.to_unsafe
      (list_of_blocks.size // BLOCK_SIZE).times do
        {% for t in 0...16 %}
          w[{{ t }}] = IO::ByteFormat::BigEndian.decode(UInt32, Slice.new(block_pointer + {{ t * 4 }}, 4))
        {% end %}
        {% for t in 16...64 %}
          %w15 = w[{{ t - 15 }}]
          %w2 = w[{{ t - 2 }}]
          %small_sigma0 = %w15.rotate_right(7) ^ %w15.rotate_right(18) ^ (%w15 >> 3)
          %small_sigma1 = %w2.rotate_right(17) ^ %w2.rotate_right(19) ^ (%w2 >> 10)
          w[{{ t }}] = %small_sigma1 &+ w[{{ t - 7 }}] &+ %small_sigma0 &+ w[{{ t - 16 }}]
        {% end %}

        a = @state[0]
        b = @state[1]
        c = @state[2]
        d = @state[3]
        e = @state[4]
        f = @state[5]
        g = @state[6]
        h = @state[7]

        {% begin %}
        {% names = %w[a b c d e f g h] %}
        {% for t in 0...64 %}
          {% ra = names[(64 - t) % 8].id %}
          {% rb = names[(65 - t) % 8].id %}
          {% rc = names[(66 - t) % 8].id %}
          {% rd = names[(67 - t) % 8].id %}
          {% re = names[(68 - t) % 8].id %}
          {% rf = names[(69 - t) % 8].id %}
          {% rg = names[(70 - t) % 8].id %}
          {% rh = names[(71 - t) % 8].id %}
          %big_sigma1 = {{ re }}.rotate_right(6) ^ {{ re }}.rotate_right(11) ^ {{ re }}.rotate_right(25)
          %choice = {{ rg }} ^ ({{ re }} & ({{ rf }} ^ {{ rg }}))
          %t1 = {{ rh }} &+ %big_sigma1 &+ %choice &+ {{ ROUND_CONSTANTS[t] }} &+ w[{{ t }}]
          %big_sigma0 = {{ ra }}.rotate_right(2) ^ {{ ra }}.rotate_right(13) ^ {{ ra }}.rotate_right(22)
          %majority = {{ rb }} ^ (({{ ra }} ^ {{ rb }}) & ({{ rb }} ^ {{ rc }}))
          {{ rd }} = {{ rd }} &+ %t1
          {{ rh }} = %t1 &+ %big_sigma0 &+ %majority
        {% end %}
        {% end %}

        @state[0] = @state[0] &+ a
        @state[1] = @state[1] &+ b
        @state[2] = @state[2] &+ c
        @state[3] = @state[3] &+ d
        @state[4] = @state[4] &+ e
        @state[5] = @state[5] &+ f
        @state[6] = @state[6] &+ g
        @state[7] = @state[7] &+ h

        block_pointer += BLOCK_SIZE
      end
    end
  end
end
