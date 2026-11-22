require "../v1/block_hash_function"

module Amber::Beryl::Crypto::Compatibility
  # MD5 (RFC 1321): a 128-bit digest.
  #
  # WARNING: MD5 is broken for collision resistance (RFC 6151). It is here
  # only to read and speak formats that require it (PostgreSQL md5
  # authentication, advisory lock ids and cache keys that must stay
  # bit-exact). Use `Amber::Beryl::Crypto.digest` for anything new.
  #
  # ```
  # Amber::Beryl::Crypto::Compatibility::MD5.hexdigest("abc")
  # # => "900150983cd24fb0d6963f7d28e17f72"
  # ```
  class MessageDigest5 < V1::BlockHashFunction
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 16

    # The number of bytes the compression function consumes per step.
    BLOCK_SIZE = 64

    @state = uninitialized UInt32[4]

    def digest_size : Int32
      DIGEST_SIZE
    end

    def block_size : Int32
      BLOCK_SIZE
    end

    private def reset_state : Nil
      @state = StaticArray[0x67452301_u32, 0xefcdab89_u32, 0x98badcfe_u32, 0x10325476_u32]
    end

    private def length_field_bytesize : Int32
      8
    end

    private def encode_message_bit_length(message_bytesize : UInt64, length_field : Bytes) : Nil
      IO::ByteFormat::LittleEndian.encode(message_bytesize << 3, length_field)
    end

    private def encode_digest(dst : Bytes) : Nil
      4.times do |word_index|
        IO::ByteFormat::LittleEndian.encode(@state[word_index], dst[word_index * 4, 4])
      end
    end

    # The sixty-four steps of RFC 1321 §3.4, written out by the macro below.
    # In step `i` the working variable that the RFC calls `a` lives in the
    # local named by `names[(64 - i) % 4]`. The sine table holds
    # `floor(2^32 * abs(sin(i + 1)))`.
    private def compress(list_of_blocks : Bytes) : Nil
      x = uninitialized UInt32[16]
      block_offset = 0
      while block_offset < list_of_blocks.size
        block = list_of_blocks[block_offset, BLOCK_SIZE]

        {% for k in 0...16 %}
          x[{{ k }}] = IO::ByteFormat::LittleEndian.decode(UInt32, block[{{ k * 4 }}, 4])
        {% end %}

        a = @state[0]
        b = @state[1]
        c = @state[2]
        d = @state[3]

        {% begin %}
        {% names = %w[a b c d] %}
        {% list_of_shifts = [[7, 12, 17, 22], [5, 9, 14, 20], [4, 11, 16, 23], [6, 10, 15, 21]] %}
        {% sine_table = [
             0xd76aa478_u32, 0xe8c7b756_u32, 0x242070db_u32, 0xc1bdceee_u32,
             0xf57c0faf_u32, 0x4787c62a_u32, 0xa8304613_u32, 0xfd469501_u32,
             0x698098d8_u32, 0x8b44f7af_u32, 0xffff5bb1_u32, 0x895cd7be_u32,
             0x6b901122_u32, 0xfd987193_u32, 0xa679438e_u32, 0x49b40821_u32,
             0xf61e2562_u32, 0xc040b340_u32, 0x265e5a51_u32, 0xe9b6c7aa_u32,
             0xd62f105d_u32, 0x02441453_u32, 0xd8a1e681_u32, 0xe7d3fbc8_u32,
             0x21e1cde6_u32, 0xc33707d6_u32, 0xf4d50d87_u32, 0x455a14ed_u32,
             0xa9e3e905_u32, 0xfcefa3f8_u32, 0x676f02d9_u32, 0x8d2a4c8a_u32,
             0xfffa3942_u32, 0x8771f681_u32, 0x6d9d6122_u32, 0xfde5380c_u32,
             0xa4beea44_u32, 0x4bdecfa9_u32, 0xf6bb4b60_u32, 0xbebfbc70_u32,
             0x289b7ec6_u32, 0xeaa127fa_u32, 0xd4ef3085_u32, 0x04881d05_u32,
             0xd9d4d039_u32, 0xe6db99e5_u32, 0x1fa27cf8_u32, 0xc4ac5665_u32,
             0xf4292244_u32, 0x432aff97_u32, 0xab9423a7_u32, 0xfc93a039_u32,
             0x655b59c3_u32, 0x8f0ccc92_u32, 0xffeff47d_u32, 0x85845dd1_u32,
             0x6fa87e4f_u32, 0xfe2ce6e0_u32, 0xa3014314_u32, 0x4e0811a1_u32,
             0xf7537e82_u32, 0xbd3af235_u32, 0x2ad7d2bb_u32, 0xeb86d391_u32,
           ] %}
        {% for i in 0...64 %}
          {% ra = names[(64 - i) % 4].id %}
          {% rb = names[(65 - i) % 4].id %}
          {% rc = names[(66 - i) % 4].id %}
          {% rd = names[(67 - i) % 4].id %}
          {% if i < 16 %}
            %mixed = ({{ rb }} & {{ rc }}) | (~{{ rb }} & {{ rd }})
            {% word_index = i %}
          {% elsif i < 32 %}
            %mixed = ({{ rb }} & {{ rd }}) | ({{ rc }} & ~{{ rd }})
            {% word_index = (5 * i + 1) % 16 %}
          {% elsif i < 48 %}
            %mixed = {{ rb }} ^ {{ rc }} ^ {{ rd }}
            {% word_index = (3 * i + 5) % 16 %}
          {% else %}
            %mixed = {{ rc }} ^ ({{ rb }} | ~{{ rd }})
            {% word_index = (7 * i) % 16 %}
          {% end %}
          %sum = {{ ra }} &+ %mixed &+ x[{{ word_index }}] &+ {{ sine_table[i] }}
          {{ ra }} = {{ rb }} &+ %sum.rotate_left({{ list_of_shifts[i // 16][i % 4] }})
        {% end %}
        {% end %}

        @state[0] = @state[0] &+ a
        @state[1] = @state[1] &+ b
        @state[2] = @state[2] &+ c
        @state[3] = @state[3] &+ d

        block_offset += BLOCK_SIZE
      end
    end
  end

  # The common name of `MessageDigest5`.
  alias MD5 = MessageDigest5
end
