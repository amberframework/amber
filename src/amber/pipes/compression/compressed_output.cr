{% unless flag?(:without_zlib) %}
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

          # Gzip header bytes before the modification time, then after it:
          # deflate method, no flags; no extra flags, unknown OS. These are
          # the bytes `Compress::Gzip::Header` writes.
          GZIP_HEADER_START = Bytes[0x1f, 0x8b, 0x08, 0x00]
          GZIP_HEADER_END   = Bytes[0x00, 0xff]

          @content_coding = ContentCoding::Undecided
          @deflater : Deflater?
          @wrote_gzip_header = false
          @crc32 : UInt32 = ::Digest::CRC32.initial
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

            if @content_coding.gzip?
              write_gzip_header
              @crc32 = ::Digest::CRC32.update(slice, @crc32)
              @uncompressed_size &+= slice.size
            end
            deflater.write(slice, @io)
          end

          # A flush before the first write sends the headers uncompressed, so
          # the body that follows stays uncompressed too, as with
          # `HTTP::CompressHandler`.
          def flush : Nil
            @content_coding = ContentCoding::Identity if @content_coding.undecided?
            if deflater = @deflater
              write_gzip_header if @content_coding.gzip?
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
              write_gzip_header if @content_coding.gzip?
              deflater.finish(@io)
              if @content_coding.gzip?
                @io.write_bytes @crc32, IO::ByteFormat::LittleEndian
                @io.write_bytes @uncompressed_size, IO::ByteFormat::LittleEndian
              end
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
              response.headers["Content-Encoding"] = "gzip"
            elsif request_headers.includes_word?("Accept-Encoding", "deflate")
              @content_coding = ContentCoding::Deflate
              response.headers["Content-Encoding"] = "deflate"
            else
              return
            end
            response.headers.delete("Content-Length")
            @deflater = @pool.checkout
          end

          private def write_gzip_header : Nil
            return if @wrote_gzip_header
            @wrote_gzip_header = true
            @io.write(GZIP_HEADER_START)
            @io.write_bytes(Time.utc.to_unix.to_u32, IO::ByteFormat::LittleEndian)
            @io.write(GZIP_HEADER_END)
          end
        end
      end
    end
  end
{% end %}
