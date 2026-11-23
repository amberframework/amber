module Amber::Mica::Brotli
  # Packs bits least-significant first into a growing byte buffer, the
  # order RFC 7932 streams use. Each write ORs its bits into the current
  # byte and stores eight bytes at once (google/brotli's BrotliWriteBits),
  # so the bytes after the write position are always zero bits. A `Mark`
  # taken before a metablock lets the encoder rewind and store the
  # metablock uncompressed instead.
  #
  # :nodoc:
  class BitWriter
    # Where the writer stood, in bits.
    record Mark, position : Int64

    # Outside the garbage collector: it grows to twice the input and holds
    # no references. Freed when the writer is collected.
    @buffer : Pointer(UInt8)
    @capacity : Int32
    @position = 0_i64

    def initialize(capacity : Int32 = 4096)
      @capacity = Math.max(capacity, 64)
      @buffer = Encode.table(UInt8, @capacity)
      @buffer[0] = 0_u8
    end

    def finalize
      @buffer = Encode.free_table(@buffer)
    end

    # Appends the low *count* bits of *value* (at most 56 bits; *value*
    # has no bits above them).
    @[AlwaysInline]
    def write(count : Int, value : Int) : Nil
      byte = (@position >> 3).to_i32!
      grow(byte + 8) if byte + 8 > @capacity
      pointer = @buffer + byte
      pointer.as(UInt64*).value = pointer.value.to_u64 | (value.to_u64! << (@position & 7))
      @position &+= count
    end

    # Makes room for *bytes* more bytes, so a metablock's writes need not
    # grow the buffer one by one.
    def reserve(bytes : Int32) : Nil
      needed = (@position >> 3).to_i32 + bytes + 8
      grow(needed) if needed > @capacity
    end

    # Pads with zero bits to the next byte boundary.
    def align : Nil
      return if @position & 7 == 0
      @position = (@position + 7) & ~7_i64
      byte = (@position >> 3).to_i32
      grow(byte + 8) if byte + 8 > @capacity
      @buffer[byte] = 0_u8
    end

    # Appends *bytes* after `align`.
    def write_bytes(bytes : Bytes) : Nil
      align
      byte = (@position >> 3).to_i32
      grow(byte + bytes.size + 8) if byte + bytes.size + 8 > @capacity
      (@buffer + byte).copy_from(bytes.to_unsafe, bytes.size)
      @position += bytes.size.to_i64 * 8
      @buffer[byte + bytes.size] = 0_u8
    end

    # The bits written since the writer started or last drained.
    def bit_size : Int64
      @position
    end

    def mark : Mark
      Mark.new(@position)
    end

    # Rewinds to *mark*, dropping everything written after it.
    def rewind(mark : Mark) : Nil
      @position = mark.position
      byte = (@position >> 3).to_i32
      @buffer[byte] &= ((1 << (@position & 7)) - 1).to_u8
    end

    # Writes the completed bytes to *io* and keeps the partial byte.
    def drain(io : IO) : Nil
      whole = (@position >> 3).to_i32
      return if whole == 0
      io.write(Slice.new(@buffer, whole))
      @buffer[0] = @buffer[whole]
      @position &= 7
      @buffer[1] = 0_u8
    end

    # Returns the completed bytes (call after `align`): a view of the
    # buffer, valid until the next write; copy it to keep it.
    def to_slice : Bytes
      Slice.new(@buffer, (@position >> 3).to_i32)
    end

    private def grow(needed : Int32) : Nil
      capacity = Math.max(needed, @capacity * 2)
      grown = LibC.realloc(@buffer.as(Void*), LibC::SizeT.new(capacity))
      raise RuntimeError.new("Brotli encoder could not allocate #{capacity} bytes") if grown.null?
      @buffer = grown.as(UInt8*)
      @capacity = capacity
    end
  end
end
