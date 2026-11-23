require "../v1/block_hash_function"
require "../processor_features"
require "../armv8_hash_instructions"
require "../x86_64_hash_instructions"

module Amber::Beryl::Crypto::Compatibility
  # SHA-1 (FIPS 180-4 §6.1): a 160-bit digest.
  #
  # WARNING: SHA-1 is broken for collision resistance. It is here only to
  # read and speak formats that require it (WebSocket handshakes, UUID v5,
  # PostgreSQL and MySQL authentication). Use `Amber::Beryl::Crypto.digest` for
  # anything new.
  #
  # ```
  # Amber::Beryl::Crypto::Compatibility::SHA1.hexdigest("abc")
  # # => "a9993e364706816aba3e25717850c26c9cd0d89d"
  # ```
  class SecureHashAlgorithm1 < V1::BlockHashFunction
    extend ::Digest::ClassMethods

    # The number of bytes in the digest.
    DIGEST_SIZE = 20

    # The number of bytes the compression function consumes per step.
    BLOCK_SIZE = 64

    @state = uninitialized UInt32[5]

    def digest_size : Int32
      DIGEST_SIZE
    end

    def block_size : Int32
      BLOCK_SIZE
    end

    private def reset_state : Nil
      @state = StaticArray[0x67452301_u32, 0xefcdab89_u32, 0x98badcfe_u32, 0x10325476_u32, 0xc3d2e1f0_u32]
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
      5.times do |word_index|
        IO::ByteFormat::BigEndian.encode(@state[word_index], dst[word_index * 4, 4])
      end
    end

    # Mixes whole blocks into the state: with the processor's SHA-1
    # instructions where it has them (`ProcessorFeatures`), with the portable
    # code below everywhere else. Kept out of line so that the program holds
    # one copy of the assembly and its table of constants per hash.
    @[NoInline]
    private def compress(list_of_blocks : Bytes) : Nil
      {% if flag?(:aarch64) || (flag?(:x86_64) && flag?(:linux)) %}
        if ProcessorFeatures::HAS_SHA1_INSTRUCTIONS
          state_pointer = pointerof(@state).as(UInt32*)
          block_pointer = list_of_blocks.to_unsafe
          block_count = (list_of_blocks.size // BLOCK_SIZE).to_u64
          return if block_count == 0
    
          {% if flag?(:aarch64) %}
            Armv8HashInstructions.compress_sha1_blocks(state_pointer, block_pointer, block_count)
          {% else %}
            X8664HashInstructions.compress_sha1_blocks(state_pointer, block_pointer, block_count)
          {% end %}
          return
        end
      {% end %}
      compress_with_portable_code(list_of_blocks)
    end

    # The eighty rounds of FIPS 180-4 §6.1.2, written out by the macro below.
    # In round `t` the working variable that the standard calls `a` lives in
    # the local named by `names[(80 - t) % 5]`.
    private def compress_with_portable_code(list_of_blocks : Bytes) : Nil
      w = uninitialized UInt32[80]
      # The loop runs once per whole block, so every read below stays
      # inside *list_of_blocks*.
      block_pointer = list_of_blocks.to_unsafe
      (list_of_blocks.size // BLOCK_SIZE).times do
        {% for t in 0...16 %}
          w[{{ t }}] = IO::ByteFormat::BigEndian.decode(UInt32, Slice.new(block_pointer + {{ t * 4 }}, 4))
        {% end %}
        {% for t in 16...80 %}
          w[{{ t }}] = (w[{{ t - 3 }}] ^ w[{{ t - 8 }}] ^ w[{{ t - 14 }}] ^ w[{{ t - 16 }}]).rotate_left(1)
        {% end %}

        a = @state[0]
        b = @state[1]
        c = @state[2]
        d = @state[3]
        e = @state[4]

        {% begin %}
        {% names = %w[a b c d e] %}
        {% for t in 0...80 %}
          {% ra = names[(80 - t) % 5].id %}
          {% rb = names[(81 - t) % 5].id %}
          {% rc = names[(82 - t) % 5].id %}
          {% rd = names[(83 - t) % 5].id %}
          {% re = names[(84 - t) % 5].id %}
          {% if t < 20 %}
            %mixed = {{ rd }} ^ ({{ rb }} & ({{ rc }} ^ {{ rd }}))
            %round_constant = 0x5a827999_u32
          {% elsif t < 40 %}
            %mixed = {{ rb }} ^ {{ rc }} ^ {{ rd }}
            %round_constant = 0x6ed9eba1_u32
          {% elsif t < 60 %}
            %mixed = {{ rc }} ^ (({{ rb }} ^ {{ rc }}) & ({{ rc }} ^ {{ rd }}))
            %round_constant = 0x8f1bbcdc_u32
          {% else %}
            %mixed = {{ rb }} ^ {{ rc }} ^ {{ rd }}
            %round_constant = 0xca62c1d6_u32
          {% end %}
          {{ re }} = {{ ra }}.rotate_left(5) &+ %mixed &+ {{ re }} &+ %round_constant &+ w[{{ t }}]
          {{ rb }} = {{ rb }}.rotate_left(30)
        {% end %}
        {% end %}

        @state[0] = @state[0] &+ a
        @state[1] = @state[1] &+ b
        @state[2] = @state[2] &+ c
        @state[3] = @state[3] &+ d
        @state[4] = @state[4] &+ e

        block_pointer += BLOCK_SIZE
      end
    end
  end

  # The common name of `SecureHashAlgorithm1`.
  alias SHA1 = SecureHashAlgorithm1
end
