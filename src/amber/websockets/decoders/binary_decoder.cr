require "./decoder"

module Amber
  module WebSockets
    module Decoders
      # Binary decoder for WebSocket messages using a simple length-prefixed format.
      #
      # This decoder provides a compact binary serialization format for WebSocket
      # messages. Each field is encoded as a length-prefixed UTF-8 string:
      #
      #   [key_length:4 bytes][key_data][value_length:4 bytes][value_data]...
      #
      # The field count is stored as the first 4 bytes. This format is suitable
      # when bandwidth efficiency is important and both client and server support
      # binary WebSocket frames.
      #
      # Since Crystal WebSocket messages arrive as strings, the binary data is
      # Base64-encoded for transport. If you receive raw binary frames, decode
      # them from Base64 first.
      #
      # Example:
      #
      # ```
      # decoder = Amber::WebSockets::Decoders::BinaryDecoder.new
      # encoded = decoder.encode({"event" => "message", "topic" => "room:1"})
      # decoded = decoder.decode(encoded)
      # decoded["event"].as_s # => "message"
      # ```
      class BinaryDecoder < Decoder
        # The largest decoded message accepted, in bytes.
        DEFAULT_MAX_FRAME_BYTES = 1_048_576

        getter max_frame_bytes : Int32

        # *max_frame_bytes* bounds the decoded message; override `decoder` in
        # a `ClientSocket` to pass a different value.
        def initialize(@max_frame_bytes : Int32 = DEFAULT_MAX_FRAME_BYTES)
          raise ArgumentError.new("max_frame_bytes must be positive, got #{@max_frame_bytes}") unless @max_frame_bytes > 0
        end

        def decode(raw : String) : JSON::Any
          # Checked before decoding: Base64 yields 3 bytes per 4 characters.
          max_encoded_bytes = (@max_frame_bytes.to_i64 + 2) // 3 * 4
          if raw.bytesize > max_encoded_bytes
            raise DecoderError.new("Failed to decode binary message: frame exceeds #{@max_frame_bytes} bytes", nil)
          end

          bytes = Base64.decode(raw)
          io = IO::Memory.new(bytes)

          field_count = read_uint32(io)
          # Each field needs at least two 4-byte length prefixes.
          remaining = io.size - io.pos
          raise IO::EOFError.new("field count #{field_count} exceeds the message size") if field_count > remaining // 8
          result = Hash(String, JSON::Any).new

          field_count.times do
            key = read_length_prefixed_string(io)
            value = read_length_prefixed_string(io)
            result[key] = JSON::Any.new(value)
          end

          unless io.pos == io.size
            raise DecoderError.new("Failed to decode binary message: #{io.size - io.pos} trailing bytes after the declared fields", raw)
          end

          JSON::Any.new(result)
        rescue ex : IO::EOFError | IndexError | Base64::Error
          raise DecoderError.new("Failed to decode binary message: #{ex.message}", raw)
        end

        def encode(payload : Hash) : String
          io = IO::Memory.new

          write_uint32(io, payload.size.to_u32)

          payload.each do |key, value|
            write_length_prefixed_string(io, key.to_s)
            write_length_prefixed_string(io, value.to_s)
          end

          Base64.strict_encode(io.to_slice)
        end

        def encode(payload : JSON::Any) : String
          hash = Hash(String, String).new
          if obj = payload.as_h?
            obj.each { |k, v| hash[k] = v.to_s }
          end
          encode(hash)
        end

        def content_type : String
          "application/octet-stream"
        end

        private def read_uint32(io : IO::Memory) : UInt32
          bytes = Bytes.new(4)
          io.read_fully(bytes)
          IO::ByteFormat::BigEndian.decode(UInt32, bytes)
        end

        private def write_uint32(io : IO, value : UInt32)
          bytes = Bytes.new(4)
          IO::ByteFormat::BigEndian.encode(value, bytes)
          io.write(bytes)
        end

        private def read_length_prefixed_string(io : IO::Memory) : String
          length = read_uint32(io)
          # The prefix is untrusted: never allocate more than the message holds.
          remaining = io.size - io.pos
          raise IO::EOFError.new("length prefix #{length} exceeds the #{remaining} bytes remaining") if length > remaining
          bytes = Bytes.new(length)
          io.read_fully(bytes)
          String.new(bytes)
        end

        private def write_length_prefixed_string(io : IO, value : String)
          bytes = value.to_slice
          write_uint32(io, bytes.size.to_u32)
          io.write(bytes)
        end
      end
    end
  end
end
