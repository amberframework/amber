require "digest/digest"
require "../error"
require "../secret_wiping"

module Amber::Beryl::Crypto::V1
  # The shared shape of MD5, SHA-1 and SHA-2: the message is cut into
  # fixed-size blocks, each block is mixed into a running state, and the last
  # block carries padding and the message length (the Merkle–Damgård
  # construction of FIPS 180-4 §5 and RFC 1321 §3).
  #
  # Each hash function supplies its block size, its compression function and
  # the layout of its length field and digest (as private methods); this class
  # supplies buffering, padding, and the `::Digest` streaming interface
  # (`update`, `final`, `reset`, `hexfinal`).
  abstract class BlockHashFunction < ::Digest
    # The largest block of any hash in this shard, in bytes (SHA-512).
    LARGEST_BLOCK_SIZE = 128

    # The largest digest of any hash in this shard, in bytes (SHA-512).
    LARGEST_DIGEST_SIZE = 64

    # Every length field in this family counts bits in at least 64 bits, so a
    # message may hold at most 2^61 - 1 bytes.
    MAXIMUM_MESSAGE_BYTESIZE = (1_u64 << 61) - 1

    # Bytes received that do not fill a block yet.
    @pending_block = StaticArray(UInt8, LARGEST_BLOCK_SIZE).new(0_u8)
    @pending_bytesize = 0
    @message_bytesize = 0_u64

    # Returns the number of bytes the compression function consumes per step.
    abstract def block_size : Int32

    # Sets the running state to the hash function's initial value.
    abstract def reset_state : Nil

    # Mixes *list_of_blocks*, whose size is a whole number of blocks, into the
    # running state.
    abstract def compress(list_of_blocks : Bytes) : Nil

    # Returns the number of bytes at the end of the last block that hold the
    # message length.
    abstract def length_field_bytesize : Int32

    # Writes the message length in bits into *length_field*.
    abstract def encode_message_bit_length(message_bytesize : UInt64, length_field : Bytes) : Nil

    # Writes the digest, taken from the running state, into *dst*.
    abstract def encode_digest(dst : Bytes) : Nil

    def initialize
      reset_state
    end

    # Makes this instance continue from the exact point *source* has reached,
    # without allocating. HMAC uses it to restart from a keyed state. Both
    # must be the same hash function.
    def copy_state_from(source : self) : Nil
      {% for instance_variable in @type.instance_vars %}
        @{{ instance_variable.name }} = source.@{{ instance_variable.name }}
      {% end %}
    end

    private def update_impl(data : Bytes) : Nil
      if data.size.to_u64 > MAXIMUM_MESSAGE_BYTESIZE - @message_bytesize
        raise MessageTooLong.new("a message for this hash holds at most #{MAXIMUM_MESSAGE_BYTESIZE} bytes")
      end
      @message_bytesize &+= data.size.to_u64

      block_bytesize = block_size
      pending = @pending_block.to_slice

      if @pending_bytesize > 0
        bytes_taken = Math.min(block_bytesize - @pending_bytesize, data.size)
        data[0, bytes_taken].copy_to(pending[@pending_bytesize, bytes_taken])
        @pending_bytesize += bytes_taken
        data = data[bytes_taken, data.size - bytes_taken]
        return if @pending_bytesize < block_bytesize

        compress(pending[0, block_bytesize])
        @pending_bytesize = 0
      end

      whole_blocks_bytesize = data.size - data.size % block_bytesize
      compress(data[0, whole_blocks_bytesize]) if whole_blocks_bytesize > 0

      remaining_bytesize = data.size - whole_blocks_bytesize
      data[whole_blocks_bytesize, remaining_bytesize].copy_to(pending[0, remaining_bytesize])
      @pending_bytesize = remaining_bytesize
    end

    private def final_impl(dst : Bytes) : Nil
      unless dst.size == digest_size
        raise OutputSizeMismatch.new("the digest is #{digest_size} bytes, the buffer holds #{dst.size}")
      end

      block_bytesize = block_size
      last_block = @pending_block.to_slice[0, block_bytesize]
      length_field_offset = block_bytesize - length_field_bytesize

      # Padding: one 0x80 byte, zeros up to the length field, then the length.
      last_block[@pending_bytesize] = 0x80_u8
      last_block[@pending_bytesize + 1, block_bytesize - @pending_bytesize - 1].fill(0_u8)
      if @pending_bytesize + 1 > length_field_offset
        compress(last_block)
        last_block.fill(0_u8)
      end
      encode_message_bit_length(@message_bytesize, last_block[length_field_offset, length_field_bytesize])
      compress(last_block)

      encode_digest(dst)
      SecretWiping.wipe(@pending_block.to_slice)
    end

    private def reset_impl : Nil
      SecretWiping.wipe(@pending_block.to_slice)
      @pending_bytesize = 0
      @message_bytesize = 0_u64
      reset_state
    end
  end
end
