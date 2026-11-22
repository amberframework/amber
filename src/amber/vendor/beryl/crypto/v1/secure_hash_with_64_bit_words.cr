require "./block_hash_function"

module Amber::Beryl::Crypto::V1
  # The SHA-2 compression function on 64-bit words (FIPS 180-4 §6.4), shared
  # by SHA-384, SHA-512 and SHA-512/256, which differ only in their initial
  # state and in how much of the final state they output.
  abstract class SecureHashWith64BitWords < BlockHashFunction
    # The number of bytes the compression function consumes per step.
    BLOCK_SIZE = 128

    @state = uninitialized UInt64[8]

    # Returns the eight initial state words of the concrete hash function.
    abstract def initial_state : StaticArray(UInt64, 8)

    def block_size : Int32
      BLOCK_SIZE
    end

    private def reset_state : Nil
      @state = initial_state
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

    # One round per constant of FIPS 180-4 §4.2.3. The rounds are written out
    # by the macro below; in round `t` the working variable that the standard
    # calls `a` lives in the local named by `names[(80 - t) % 8]`, so the
    # standard's "shift every variable down one" costs nothing at run time.
    private def compress(list_of_blocks : Bytes) : Nil
      w = uninitialized UInt64[80]
      block_offset = 0
      while block_offset < list_of_blocks.size
        block = list_of_blocks[block_offset, BLOCK_SIZE]

        {% for t in 0...16 %}
          w[{{ t }}] = IO::ByteFormat::BigEndian.decode(UInt64, block[{{ t * 8 }}, 8])
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
        {% round_constants = [
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
           ] %}
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
          %choice = ({{ re }} & {{ rf }}) ^ (~{{ re }} & {{ rg }})
          %t1 = {{ rh }} &+ %big_sigma1 &+ %choice &+ {{ round_constants[t] }} &+ w[{{ t }}]
          %big_sigma0 = {{ ra }}.rotate_right(28) ^ {{ ra }}.rotate_right(34) ^ {{ ra }}.rotate_right(39)
          %majority = ({{ ra }} & {{ rb }}) ^ ({{ ra }} & {{ rc }}) ^ ({{ rb }} & {{ rc }})
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

        block_offset += BLOCK_SIZE
      end
    end
  end
end
