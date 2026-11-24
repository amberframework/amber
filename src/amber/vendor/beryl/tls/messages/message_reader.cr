module Amber::Beryl::TLS::Messages
  # Reads the TLS presentation language (RFC 9846 §3) from bytes, sans-IO.
  # Every read checks the bytes left before it indexes; a short or
  # overlong input raises `Error` with `decode_error`, never `IndexError`.
  class MessageReader
    getter offset : Int32 = 0

    def initialize(@bytes : Bytes)
    end

    def remaining : Int32
      @bytes.size - @offset
    end

    def at_end? : Bool
      @offset == @bytes.size
    end

    def read_u8 : UInt8
      ensure_available(1)
      value = @bytes[@offset]
      @offset += 1
      value
    end

    def read_u16 : UInt16
      ensure_available(2)
      value = (@bytes[@offset].to_u16 << 8) | @bytes[@offset + 1]
      @offset += 2
      value
    end

    def read_u24 : Int32
      ensure_available(3)
      value = (@bytes[@offset].to_i << 16) | (@bytes[@offset + 1].to_i << 8) | @bytes[@offset + 2].to_i
      @offset += 3
      value
    end

    def read_u32 : UInt32
      ensure_available(4)
      value = (@bytes[@offset].to_u32 << 24) | (@bytes[@offset + 1].to_u32 << 16) | (@bytes[@offset + 2].to_u32 << 8) | @bytes[@offset + 3]
      @offset += 4
      value
    end

    def read_bytes(count : Int32) : Bytes
      ensure_available(count)
      value = @bytes[@offset, count]
      @offset += count
      value
    end

    # Reads a vector with a one-byte length.
    def read_vector8(minimum : Int32 = 0) : Bytes
      read_vector(read_u8.to_i, minimum)
    end

    # Reads a vector with a two-byte length.
    def read_vector16(minimum : Int32 = 0) : Bytes
      read_vector(read_u16.to_i, minimum)
    end

    # Reads a vector with a three-byte length.
    def read_vector24(minimum : Int32 = 0) : Bytes
      read_vector(read_u24, minimum)
    end

    # Raises unless every byte was read.
    def finish : Nil
      raise Error.new("#{remaining} bytes after the end of a structure", AlertDescription::DecodeError) unless at_end?
    end

    private def read_vector(length : Int32, minimum : Int32) : Bytes
      raise Error.new("a vector of #{length} bytes, below its minimum of #{minimum}", AlertDescription::DecodeError) if length < minimum
      read_bytes(length)
    end

    private def ensure_available(count : Int32) : Nil
      if count > remaining
        raise Error.new("a structure needs #{count} bytes, #{remaining} are left", AlertDescription::DecodeError)
      end
    end
  end

  # Writes the TLS presentation language.
  class MessageWriter
    def initialize
      @output = IO::Memory.new
    end

    def write_u8(value : Int) : Nil
      @output.write_byte(value.to_u8)
    end

    def write_u16(value : Int) : Nil
      @output.write_byte((value >> 8).to_u8!)
      @output.write_byte((value & 0xFF).to_u8!)
    end

    def write_u24(value : Int) : Nil
      @output.write_byte((value >> 16).to_u8!)
      @output.write_byte(((value >> 8) & 0xFF).to_u8!)
      @output.write_byte((value & 0xFF).to_u8!)
    end

    def write_u32(value : Int) : Nil
      write_u16(value >> 16)
      write_u16(value & 0xFFFF)
    end

    def write_bytes(bytes : Bytes) : Nil
      @output.write(bytes)
    end

    def write_vector8(bytes : Bytes) : Nil
      raise ArgumentError.new("a vector of #{bytes.size} bytes in a one-byte length") if bytes.size > 0xFF
      write_u8(bytes.size)
      write_bytes(bytes)
    end

    def write_vector16(bytes : Bytes) : Nil
      raise ArgumentError.new("a vector of #{bytes.size} bytes in a two-byte length") if bytes.size > 0xFFFF
      write_u16(bytes.size)
      write_bytes(bytes)
    end

    def write_vector24(bytes : Bytes) : Nil
      raise ArgumentError.new("a vector of #{bytes.size} bytes in a three-byte length") if bytes.size > 0xFFFFFF
      write_u24(bytes.size)
      write_bytes(bytes)
    end

    # Writes what the block writes, prefixed with its two-byte length.
    def write_vector16(& : MessageWriter ->) : Nil
      inner = MessageWriter.new
      yield inner
      write_vector16(inner.to_slice)
    end

    # Writes what the block writes, prefixed with its one-byte length.
    def write_vector8(& : MessageWriter ->) : Nil
      inner = MessageWriter.new
      yield inner
      write_vector8(inner.to_slice)
    end

    # Writes what the block writes, prefixed with its three-byte length.
    def write_vector24(& : MessageWriter ->) : Nil
      inner = MessageWriter.new
      yield inner
      write_vector24(inner.to_slice)
    end

    def to_slice : Bytes
      @output.to_slice
    end
  end
end
