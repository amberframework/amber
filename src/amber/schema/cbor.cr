module Amber::Schema::CBOR
  extend self

  MAX_BODY_BYTES = 1_048_576
  MAX_DEPTH      =        32
  MAX_ITEMS      =    16_384
  MAX_TEXT_BYTES = 1_048_576

  class DecodeError < RequestParseError
    def initialize(message : String)
      super("Invalid CBOR: #{message}", "invalid_cbor")
    end
  end

  def decode_object(io : IO) : Hash(String, JSON::Any)
    reader = Reader.new(io)
    value = reader.read_json
    reader.finish!
    value.as_h? || raise DecodeError.new("request body must be a map")
  rescue ex : DecodeError
    raise ex
  rescue ex
    raise DecodeError.new(ex.message || "malformed document")
  end

  def encode(data : Hash(String, JSON::Any)) : Bytes
    io = IO::Memory.new
    write_json(io, JSON::Any.new(data))
    io.to_slice.dup
  end

  def write_json(io : IO, value : JSON::Any) : Nil
    case raw = value.raw
    when Nil
      io.write_byte(0xf6_u8)
    when Bool
      io.write_byte(raw ? 0xf5_u8 : 0xf4_u8)
    when Int64
      write_int(io, raw)
    when Float64
      raise ArgumentError.new("CBOR cannot encode non-finite JSON numbers") unless raw.finite?
      io.write_byte(0xfb_u8)
      io.write_bytes(raw, IO::ByteFormat::BigEndian)
    when String
      write_text(io, raw)
    when Array(JSON::Any)
      write_head(io, 4_u8, raw.size.to_u64)
      raw.each { |item| write_json(io, item) }
    when Hash(String, JSON::Any)
      # Length-first then bytewise ordering is deterministic and suitable for
      # signed/encrypted protocols without changing the application contract.
      keys = raw.keys.sort_by { |key| {key.bytesize, key} }
      write_head(io, 5_u8, keys.size.to_u64)
      keys.each do |key|
        write_text(io, key)
        write_json(io, raw[key])
      end
    end
  end

  def write_head(io : IO, major : UInt8, value : UInt64) : Nil
    prefix = major << 5
    case value
    when 0_u64...24_u64
      io.write_byte(prefix | value.to_u8)
    when 24_u64..UInt8::MAX.to_u64
      io.write_byte(prefix | 24_u8)
      io.write_byte(value.to_u8)
    when (UInt8::MAX.to_u64 + 1)..UInt16::MAX.to_u64
      io.write_byte(prefix | 25_u8)
      io.write_bytes(value.to_u16, IO::ByteFormat::BigEndian)
    when (UInt16::MAX.to_u64 + 1)..UInt32::MAX.to_u64
      io.write_byte(prefix | 26_u8)
      io.write_bytes(value.to_u32, IO::ByteFormat::BigEndian)
    else
      io.write_byte(prefix | 27_u8)
      io.write_bytes(value, IO::ByteFormat::BigEndian)
    end
  end

  def write_int(io : IO, value : Int64) : Nil
    if value >= 0
      write_head(io, 0_u8, value.to_u64)
    else
      write_head(io, 1_u8, (-1_i128 - value.to_i128).to_u64)
    end
  end

  def write_bytes(io : IO, value : Bytes) : Nil
    write_head(io, 2_u8, value.size.to_u64)
    io.write(value)
  end

  def write_text(io : IO, value : String) : Nil
    write_head(io, 3_u8, value.bytesize.to_u64)
    io.write(value.to_slice)
  end

  class Reader
    @bytes_read = 0

    def initialize(@io : IO, @max_bytes = MAX_BODY_BYTES)
    end

    def read_json(depth = 0) : JSON::Any
      raise DecodeError.new("nesting exceeds #{MAX_DEPTH}") if depth > MAX_DEPTH
      initial = read_byte
      major = initial >> 5
      additional = initial & 0x1f

      case major
      when 0
        integer = read_argument(additional)
        raise DecodeError.new("integer exceeds Int64") if integer > Int64::MAX.to_u64
        JSON::Any.new(integer.to_i64)
      when 1
        integer = read_argument(additional)
        raise DecodeError.new("negative integer exceeds Int64") if integer > Int64::MAX.to_u64
        JSON::Any.new(-1_i64 - integer.to_i64)
      when 2
        raise DecodeError.new("byte strings are not a JSON-compatible schema value")
      when 3
        JSON::Any.new(read_text_argument(additional))
      when 4
        count = checked_items(read_argument(additional))
        JSON::Any.new(Array(JSON::Any).new(count) { read_json(depth + 1) })
      when 5
        count = checked_items(read_argument(additional))
        object = {} of String => JSON::Any
        count.times do
          key = read_text
          raise DecodeError.new("duplicate map key '#{key}'") if object.has_key?(key)
          object[key] = read_json(depth + 1)
        end
        JSON::Any.new(object)
      when 6
        read_argument(additional)
        read_json(depth + 1)
      when 7
        read_simple(additional)
      else
        raise DecodeError.new("unsupported major type #{major}")
      end
    end

    def read_tag : UInt64
      major, argument = read_head
      raise DecodeError.new("expected tag") unless major == 6
      argument
    end

    def read_array_size : Int32
      read_size(4, "array")
    end

    def read_map_size : Int32
      read_size(5, "map")
    end

    def read_int : Int64
      major, argument = read_head
      case major
      when 0
        raise DecodeError.new("integer exceeds Int64") if argument > Int64::MAX.to_u64
        argument.to_i64
      when 1
        raise DecodeError.new("negative integer exceeds Int64") if argument > Int64::MAX.to_u64
        -1_i64 - argument.to_i64
      else
        raise DecodeError.new("expected integer")
      end
    end

    def read_bytes : Bytes
      major, argument = read_head
      raise DecodeError.new("expected byte string") unless major == 2
      read_blob(argument, "byte string")
    end

    def read_text : String
      major, argument = read_head
      raise DecodeError.new("expected text string") unless major == 3
      text_from(read_blob(argument, "text string"))
    end

    def finish! : Nil
      if extra = @io.read_byte
        @bytes_read += 1
        raise DecodeError.new("trailing bytes after document")
      end
    end

    private def read_head : Tuple(UInt8, UInt64)
      initial = read_byte
      {initial >> 5, read_argument(initial & 0x1f)}
    end

    private def read_size(expected : Int32, label : String) : Int32
      major, argument = read_head
      raise DecodeError.new("expected #{label}") unless major == expected
      checked_items(argument)
    end

    private def read_text_argument(additional : UInt8) : String
      text_from(read_blob(read_argument(additional), "text string"))
    end

    private def text_from(bytes : Bytes) : String
      value = String.new(bytes)
      raise DecodeError.new("text is not valid UTF-8") unless value.valid_encoding?
      value
    end

    private def read_simple(additional : UInt8) : JSON::Any
      case additional
      when 20 then JSON::Any.new(false)
      when 21 then JSON::Any.new(true)
      when 22 then JSON::Any.new(nil)
      when 26
        value = read_float32.to_f64
        raise DecodeError.new("non-finite float") unless value.finite?
        JSON::Any.new(value)
      when 27
        value = read_float64
        raise DecodeError.new("non-finite float") unless value.finite?
        JSON::Any.new(value)
      else
        raise DecodeError.new("unsupported simple or floating-point value")
      end
    end

    private def read_float32 : Float32
      bytes = read_exact(4)
      IO::ByteFormat::BigEndian.decode(Float32, bytes)
    end

    private def read_float64 : Float64
      bytes = read_exact(8)
      IO::ByteFormat::BigEndian.decode(Float64, bytes)
    end

    private def read_argument(additional : UInt8) : UInt64
      case additional
      when 0_u8...24_u8 then additional.to_u64
      when 24_u8        then read_byte.to_u64
      when 25_u8        then IO::ByteFormat::BigEndian.decode(UInt16, read_exact(2)).to_u64
      when 26_u8        then IO::ByteFormat::BigEndian.decode(UInt32, read_exact(4)).to_u64
      when 27_u8        then IO::ByteFormat::BigEndian.decode(UInt64, read_exact(8))
      else
        raise DecodeError.new("indefinite-length and reserved items are unsupported")
      end
    end

    private def checked_items(value : UInt64) : Int32
      raise DecodeError.new("collection exceeds #{MAX_ITEMS} items") if value > MAX_ITEMS
      value.to_i32
    end

    private def read_blob(length : UInt64, label : String) : Bytes
      raise DecodeError.new("#{label} exceeds #{MAX_TEXT_BYTES} bytes") if length > MAX_TEXT_BYTES
      read_exact(length.to_i)
    end

    private def read_byte : UInt8
      enforce_limit(1)
      @io.read_byte || raise DecodeError.new("unexpected end of input")
    end

    private def read_exact(length : Int32) : Bytes
      enforce_limit(length)
      bytes = Bytes.new(length)
      @io.read_fully(bytes)
      bytes
    rescue IO::EOFError
      raise DecodeError.new("unexpected end of input")
    end

    private def enforce_limit(increment : Int32) : Nil
      @bytes_read += increment
      raise DecodeError.new("body exceeds #{@max_bytes} bytes") if @bytes_read > @max_bytes
    end
  end
end
