{% unless flag?(:without_zlib) %}
  require "digest/adler32"
  require "digest/crc32"

  module Amber
    module Pipe
      class Compression < Base
        # The response output while `Compression` is in the pipeline. On the
        # first write it decides, as `HTTP::CompressHandler` does, whether to
        # gzip, deflate, or pass the body through, and borrows a compressor
        # from the pool only when it compresses.
        #
        # :nodoc:
        class CompressedOutput < IO
          enum ContentCoding
            Undecided
            Identity
            Gzip
            Deflate
          end

          # Whether `Content-Encoding: deflate` carries a zlib stream (a
          # two-byte header and an Adler-32 trailer around the DEFLATE data),
          # as RFC 9110 defines it. `HTTP::CompressHandler` writes that from
          # Crystal 1.22.0 on and bare DEFLATE data before, so this pipe
          # follows the compiler it is built with.
          ZLIB_FRAMED_DEFLATE = {{ compare_versions(Crystal::VERSION, "1.22.0") >= 0 }}

          # Gzip header bytes before the modification time, then after it:
          # deflate method, no flags; no extra flags, unknown OS. These are
          # the bytes `Compress::Gzip::Header` writes.
          GZIP_HEADER_START = Bytes[0x1f, 0x8b, 0x08, 0x00]
          GZIP_HEADER_END   = Bytes[0x00, 0xff]

          @content_coding = ContentCoding::Undecided
          @deflater : Deflater?
          @wrote_header = false
          @checksum : UInt32 = 0
          @uncompressed_size : UInt32 = 0
          @closed = false

          def initialize(@io : IO, @context : HTTP::Server::Context, @pool : DeflaterPool)
          end

          def read(slice : Bytes) : NoReturn
            raise NotImplementedError.new("read")
          end

          def write(slice : Bytes) : Nil
            raise IO::Error.new("Closed stream") if @closed
            choose_encoding if @content_coding.undecided?
            deflater = @deflater
            return @io.write(slice) unless deflater
            return if slice.empty?

            write_header
            deflater.write(slice, @io)
            update_checksum(slice)
          end

          # A flush before the first write sends the headers uncompressed, so
          # the body that follows stays uncompressed too, as with
          # `HTTP::CompressHandler`.
          def flush : Nil
            @content_coding = ContentCoding::Identity if @content_coding.undecided?
            if deflater = @deflater
              write_header
              deflater.flush(@io)
            end
            @io.flush
          end

          def close : Nil
            return if @closed
            @closed = true
            deflater = @deflater
            return @io.close unless deflater

            begin
              write_header
              deflater.finish(@io)
              write_trailer
            ensure
              @deflater = nil
              @pool.checkin(deflater)
            end
            @io.close
          end

          def closed? : Bool
            @closed
          end

          private def choose_encoding : Nil
            @content_coding = ContentCoding::Identity
            response = @context.response
            return if response.headers.has_key?("Content-Encoding")

            request_headers = @context.request.headers
            if request_headers.includes_word?("Accept-Encoding", "gzip")
              @content_coding = ContentCoding::Gzip
              @checksum = ::Digest::CRC32.initial
              response.headers["Content-Encoding"] = "gzip"
            elsif request_headers.includes_word?("Accept-Encoding", "deflate")
              @content_coding = ContentCoding::Deflate
              @checksum = ::Digest::Adler32.initial
              response.headers["Content-Encoding"] = "deflate"
            else
              return
            end
            response.headers.delete("Content-Length")
            @deflater = @pool.checkout
          end

          private def write_header : Nil
            return if @wrote_header
            @wrote_header = true
            if @content_coding.gzip?
              @io.write(GZIP_HEADER_START)
              @io.write_bytes(Time.utc.to_unix.to_u32, IO::ByteFormat::LittleEndian)
              @io.write(GZIP_HEADER_END)
            elsif ZLIB_FRAMED_DEFLATE
              @io.write_byte 0x78_u8
              @io.write_byte zlib_flags
            end
          end

          # The FLG byte `Compress::Zlib::Writer` writes: the level class in
          # the top two bits, then a check value that makes CMF*256+FLG a
          # multiple of 31.
          private def zlib_flags : UInt8
            level_class = case @pool.level
                          when 0..1  then 0_u8
                          when 2..5  then 1_u8
                          when 6, -1 then 2_u8
                          else            3_u8
                          end
            flags = level_class << 6
            flags + (31 - (0x78_u16 * 256 + flags.to_u16).remainder(31)).to_u8
          end

          private def update_checksum(slice : Bytes) : Nil
            if @content_coding.gzip?
              @checksum = ::Digest::CRC32.update(slice, @checksum)
              @uncompressed_size &+= slice.size
            elsif ZLIB_FRAMED_DEFLATE
              @checksum = ::Digest::Adler32.update(slice, @checksum)
            end
          end

          private def write_trailer : Nil
            if @content_coding.gzip?
              @io.write_bytes @checksum, IO::ByteFormat::LittleEndian
              @io.write_bytes @uncompressed_size, IO::ByteFormat::LittleEndian
            elsif ZLIB_FRAMED_DEFLATE
              @io.write_bytes @checksum, IO::ByteFormat::BigEndian
            end
          end
        end
      end
    end
  end
{% end %}
