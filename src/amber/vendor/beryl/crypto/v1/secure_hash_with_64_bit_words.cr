require "./block_hash_function"
require "../processor_features"
require "../armv8_hash_instructions"
require "../x86_64_hash_instructions"

module Amber::Beryl::Crypto::V1
  # The SHA-2 compression function on 64-bit words (FIPS 180-4 §6.4), shared
  # by SHA-384, SHA-512 and SHA-512/256, which differ only in their initial
  # state and in how much of the final state they output.
  abstract class SecureHashWith64BitWords < BlockHashFunction
    # The number of bytes the compression function consumes per step.
    BLOCK_SIZE = 128

    # The eighty round constants of FIPS 180-4 §4.2.3.
    ROUND_CONSTANTS = {
      0x428a2f98d728ae22_u64, 0x7137449123ef65cd_u64, 0xb5c0fbcfec4d3b2f_u64, 0xe9b5dba58189dbbc_u64,
      0x3956c25bf348b538_u64, 0x59f111f1b605d019_u64, 0x923f82a4af194f9b_u64, 0xab1c5ed5da6d8118_u64,
      0xd807aa98a3030242_u64, 0x12835b0145706fbe_u64, 0x243185be4ee4b28c_u64, 0x550c7dc3d5ffb4e2_u64,
      0x72be5d74f27b896f_u64, 0x80deb1fe3b1696b1_u64, 0x9bdc06a725c71235_u64, 0xc19bf174cf692694_u64,
      0xe49b69c19ef14ad2_u64, 0xefbe4786384f25e3_u64, 0x0fc19dc68b8cd5b5_u64, 0x240ca1cc77ac9c65_u64,
      0x2de92c6f592b0275_u64, 0x4a7484aa6ea6e483_u64, 0x5cb0a9dcbd41fbd4_u64, 0x76f988da831153b5_u64,
      0x983e5152ee66dfab_u64, 0xa831c66d2db43210_u64, 0xb00327c898fb213f_u64, 0xbf597fc7beef0ee4_u64,
      0xc6e00bf33da88fc2_u64, 0xd5a79147930aa725_u64, 0x06ca6351e003826f_u64, 0x142929670a0e6e70_u64,
      0x27b70a8546d22ffc_u64, 0x2e1b21385c26c926_u64, 0x4d2c6dfc5ac42aed_u64, 0x53380d139d95b3df_u64,
      0x650a73548baf63de_u64, 0x766a0abb3c77b2a8_u64, 0x81c2c92e47edaee6_u64, 0x92722c851482353b_u64,
      0xa2bfe8a14cf10364_u64, 0xa81a664bbc423001_u64, 0xc24b8b70d0f89791_u64, 0xc76c51a30654be30_u64,
      0xd192e819d6ef5218_u64, 0xd69906245565a910_u64, 0xf40e35855771202a_u64, 0x106aa07032bbd1b8_u64,
      0x19a4c116b8d2d0c8_u64, 0x1e376c085141ab53_u64, 0x2748774cdf8eeb99_u64, 0x34b0bcb5e19b48a8_u64,
      0x391c0cb3c5c95a63_u64, 0x4ed8aa4ae3418acb_u64, 0x5b9cca4f7763e373_u64, 0x682e6ff3d6b2b8a3_u64,
      0x748f82ee5defb2fc_u64, 0x78a5636f43172f60_u64, 0x84c87814a1f0ab72_u64, 0x8cc702081a6439ec_u64,
      0x90befffa23631e28_u64, 0xa4506cebde82bde9_u64, 0xbef9a3f7b2c67915_u64, 0xc67178f2e372532b_u64,
      0xca273eceea26619c_u64, 0xd186b8c721c0c207_u64, 0xeada7dd6cde0eb1e_u64, 0xf57d4f7fee6ed178_u64,
      0x06f067aa72176fba_u64, 0x0a637dc5a2c898a6_u64, 0x113f9804bef90dae_u64, 0x1b710b35131c471b_u64,
      0x28db77f523047d84_u64, 0x32caab7b40c72493_u64, 0x3c9ebe0a15c9bebc_u64, 0x431d67c49c100d4c_u64,
      0x4cc5d4becb3e42b6_u64, 0x597f299cfc657e2a_u64, 0x5fcb6fab3ad6faec_u64, 0x6c44198c4a475817_u64,
    }

    @state = uninitialized UInt64[8]

    # Returns the eight initial state words of the concrete hash function.
    abstract def initial_state : StaticArray(UInt64, 8)

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
      16
    end

    # The length field is 128 bits wide; the high 64 bits hold the three bits
    # that leave the top of the byte count when it becomes a bit count.
    private def encode_message_bit_length(message_bytesize : UInt64, length_field : Bytes) : Nil
      IO::ByteFormat::BigEndian.encode(message_bytesize >> 61, length_field[0, 8])
      IO::ByteFormat::BigEndian.encode(message_bytesize << 3, length_field[8, 8])
    end

    private def encode_digest(dst : Bytes) : Nil
      (dst.size // 8).times do |word_index|
        IO::ByteFormat::BigEndian.encode(@state[word_index], dst[word_index * 8, 8])
      end
    end

    # Whether `compress` runs the x86-64 assembly with the vector message
    # schedule (`X8664HashInstructions.compress_sha512_blocks`): on a
    # processor with AVX2, BMI1 and BMI2, unless the program was compiled
    # with `-Dberyl_portable_hashes`.
    {% if flag?(:x86_64) && !flag?(:beryl_portable_hashes) %}
      HAS_VECTOR_MESSAGE_SCHEDULE = ProcessorFeatures::HAS_AVX2 && ProcessorFeatures::HAS_BIT_MANIPULATION_INSTRUCTIONS
    {% else %}
      HAS_VECTOR_MESSAGE_SCHEDULE = false
    {% end %}

    # Names the code `compress` runs on this processor, for benchmarks and
    # test logs.
    def self.compression_in_use : String
      if ProcessorFeatures::HAS_SHA512_INSTRUCTIONS
        "the ARMv8 SHA512 instructions"
      elsif HAS_VECTOR_MESSAGE_SCHEDULE && ProcessorFeatures::HAS_AVX512
        "AVX-512 message schedule with BMI2 rounds"
      elsif HAS_VECTOR_MESSAGE_SCHEDULE
        "AVX2 message schedule with BMI2 rounds"
      else
        "portable code"
      end
    end

    # Mixes *block_count* blocks at *block_pointer* into the eight words at
    # *state_pointer* with the x86-64 assembly: two blocks per statement
    # while two are left, then the last one alone. Defined once for every
    # hash of this family, so the program holds one copy of each statement.
    @[NoInline]
    protected def self.compress_with_vector_message_schedule(state_pointer : UInt64*, block_pointer : UInt8*, block_count : Int32) : Nil
      {% if flag?(:x86_64) %}
        if ProcessorFeatures::HAS_AVX512
          (block_count // 2).times do
            X8664HashInstructions.compress_sha512_blocks(state_pointer, block_pointer, ::Amber::Beryl::Crypto::V1::SecureHashWith64BitWords::ROUND_CONSTANTS, true, true)
            block_pointer += 2 * BLOCK_SIZE
          end
          if block_count.odd?
            X8664HashInstructions.compress_sha512_blocks(state_pointer, block_pointer, ::Amber::Beryl::Crypto::V1::SecureHashWith64BitWords::ROUND_CONSTANTS, false, true)
          end
        else
          (block_count // 2).times do
            X8664HashInstructions.compress_sha512_blocks(state_pointer, block_pointer, ::Amber::Beryl::Crypto::V1::SecureHashWith64BitWords::ROUND_CONSTANTS, true, false)
            block_pointer += 2 * BLOCK_SIZE
          end
          if block_count.odd?
            X8664HashInstructions.compress_sha512_blocks(state_pointer, block_pointer, ::Amber::Beryl::Crypto::V1::SecureHashWith64BitWords::ROUND_CONSTANTS, false, false)
          end
        end
      {% end %}
    end

    # Mixes whole blocks into the state: with the processor's SHA-512
    # instructions where it has them (`ProcessorFeatures`), with the x86-64
    # vector schedule where the processor has AVX2 and BMI2, with the
    # portable code below everywhere else. Kept out of line so that the
    # program holds one copy of the assembly and its table of constants per
    # hash.
    @[NoInline]
    private def compress(list_of_blocks : Bytes) : Nil
      {% if flag?(:x86_64) %}
        if HAS_VECTOR_MESSAGE_SCHEDULE
          block_count = list_of_blocks.size // BLOCK_SIZE
          return if block_count == 0

          SecureHashWith64BitWords.compress_with_vector_message_schedule(pointerof(@state).as(UInt64*), list_of_blocks.to_unsafe, block_count)
          return
        end
      {% end %}
      {% if flag?(:aarch64) %}
        if ProcessorFeatures::HAS_SHA512_INSTRUCTIONS
          state_pointer = pointerof(@state).as(UInt64*)
          block_pointer = list_of_blocks.to_unsafe
          block_count = (list_of_blocks.size // BLOCK_SIZE).to_u64
          return if block_count == 0

          Armv8HashInstructions.compress_sha512_blocks(state_pointer, block_pointer, block_count, ::Amber::Beryl::Crypto::V1::SecureHashWith64BitWords::ROUND_CONSTANTS)
          return
        end
      {% end %}
      compress_with_portable_code(list_of_blocks)
    end

    # One round per constant of FIPS 180-4 §4.2.3. The rounds are written out
    # by the macro below; in round `t` the working variable that the standard
    # calls `a` lives in the local named by `names[(80 - t) % 8]`, so the
    # standard's "shift every variable down one" costs nothing at run time.
    # Ch and Maj are written in their equal forms with fewer operations:
    # Ch(e, f, g) = g ^ (e & (f ^ g)) and Maj(a, b, c) = b ^ ((a ^ b) & (b ^ c)).
    private def compress_with_portable_code(list_of_blocks : Bytes) : Nil
      w = uninitialized UInt64[80]
      # The loop runs once per whole block, so every read below stays
      # inside *list_of_blocks*.
      block_pointer = list_of_blocks.to_unsafe
      (list_of_blocks.size // BLOCK_SIZE).times do
        {% for t in 0...16 %}
          w[{{ t }}] = IO::ByteFormat::BigEndian.decode(UInt64, Slice.new(block_pointer + {{ t * 8 }}, 8))
        {% end %}
        {% for t in 16...80 %}
          %w15 = w[{{ t - 15 }}]
          %w2 = w[{{ t - 2 }}]
          %small_sigma0 = %w15.rotate_right(1) ^ %w15.rotate_right(8) ^ (%w15 >> 7)
          %small_sigma1 = %w2.rotate_right(19) ^ %w2.rotate_right(61) ^ (%w2 >> 6)
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
        {% for t in 0...80 %}
          {% ra = names[(80 - t) % 8].id %}
          {% rb = names[(81 - t) % 8].id %}
          {% rc = names[(82 - t) % 8].id %}
          {% rd = names[(83 - t) % 8].id %}
          {% re = names[(84 - t) % 8].id %}
          {% rf = names[(85 - t) % 8].id %}
          {% rg = names[(86 - t) % 8].id %}
          {% rh = names[(87 - t) % 8].id %}
          %big_sigma1 = {{ re }}.rotate_right(14) ^ {{ re }}.rotate_right(18) ^ {{ re }}.rotate_right(41)
          %choice = {{ rg }} ^ ({{ re }} & ({{ rf }} ^ {{ rg }}))
          %t1 = {{ rh }} &+ %big_sigma1 &+ %choice &+ {{ ROUND_CONSTANTS[t] }} &+ w[{{ t }}]
          %big_sigma0 = {{ ra }}.rotate_right(28) ^ {{ ra }}.rotate_right(34) ^ {{ ra }}.rotate_right(39)
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
