module Amber::Mica::Brotli
  # Packs bits least-significant first into a growing byte buffer, the
  # order RFC 7932 streams use. A `Mark` taken before a metablock lets the
  # encoder rewind and store the metablock uncompressed instead.
  #
  # :nodoc:
  class BitWriter
    # Where the writer stood: bytes done, and the bits not yet a byte.
    record Mark, size : Int32, bits : UInt64, count : Int32

    @buffer : Bytes
    @size = 0
    @bits = 0_u64
    @count = 0

    def initialize(capacity : Int32 = 4096)
      @buffer = Bytes.new(Math.max(capacity, 64))
    end

    # Appends the low *count* bits of *value* (at most 32 bits).
    @[AlwaysInline]
    def write(count : Int32, value : Int) : Nil
      @bits |= value.to_u64! << @count
      @count += count
      return if @count < 32
      ensure_room(8)
      (@buffer.to_unsafe + @size).as(UInt32*).value = @bits.to_u32!
      @size += 4
      @bits >>= 32
      @count -= 32
    end

    # Pads with zero bits to the next byte boundary and moves whole bytes
    # into the buffer.
    def align : Nil
      @count = (@count + 7) & ~7
      settle
    end

    # Appends *bytes* after `align`.
    def write_bytes(bytes : Bytes) : Nil
      align
      ensure_room(bytes.size)
      (@buffer.to_unsafe + @size).copy_from(bytes.to_unsafe, bytes.size)
      @size += bytes.size
    end

    # The bits written since `clear`.
    def bit_size : Int64
      @size.to_i64 * 8 + @count
    end

    def mark : Mark
      Mark.new(@size, @bits, @count)
    end

    # Rewinds to *mark*, dropping everything written after it.
    def rewind(mark : Mark) : Nil
      @size = mark.size
      @bits = mark.bits
      @count = mark.count
    end

    # Writes the completed bytes to *io* and keeps the partial byte.
    def drain(io : IO) : Nil
      settle
      io.write(@buffer[0, @size]) if @size > 0
      @size = 0
    end

    # Returns the completed bytes (call after `align`).
    def to_slice : Bytes
      settle
      @buffer[0, @size]
    end

    private def settle : Nil
      ensure_room(8)
      while @count >= 8
        @buffer[@size] = @bits.to_u8!
        @size += 1
        @bits >>= 8
        @count -= 8
      end
    end

    private def ensure_room(extra : Int32) : Nil
      needed = @size + extra
      return if needed <= @buffer.size
      grown = Bytes.new(Math.max(needed, @buffer.size * 2))
      grown.copy_from(@buffer.to_unsafe, @size)
      @buffer = grown
    end
  end
end
