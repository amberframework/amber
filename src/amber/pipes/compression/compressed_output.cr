module Amber
  module Pipe
    class Compression < Base
      # The response output while `Compression` is in the pipeline. On the
      # first write it decides, as `HTTP::CompressHandler` does, whether to
      # gzip, deflate, or pass the body through, and builds a compressor only
      # when it compresses.
      #
      # :nodoc:
      class CompressedOutput < IO
        # Whether `Content-Encoding: deflate` carries a zlib stream (a
        # two-byte header and an Adler-32 trailer around the DEFLATE data),
        # as RFC 9110 defines it. `HTTP::CompressHandler` writes that from
        # Crystal 1.22.0 on and bare DEFLATE data before, and this pipe
        # follows the compiler it is built with.
        ZLIB_FRAMED_DEFLATE = {{ compare_versions(Crystal::VERSION, "1.22.0") >= 0 }}

        # Nil until the first write or flush decides the content coding, and
        # nil from then on for a body that passes through uncompressed.
        @compressor : Amber::Mica::Deflate::StreamWriter?
        @is_decided = false
        @closed = false

        def initialize(@io : IO, @context : HTTP::Server::Context, @level : Int32)
        end

        def read(slice : Bytes) : NoReturn
          raise NotImplementedError.new("read")
        end

        def write(slice : Bytes) : Nil
          raise IO::Error.new("Closed stream") if @closed
          choose_encoding unless @is_decided
          compressor = @compressor
          return @io.write(slice) unless compressor

          compressor.write(slice)
        end

        # A flush before the first write sends the headers uncompressed, so
        # the body that follows stays uncompressed too, as with
        # `HTTP::CompressHandler`. A flush of a compressed body ends on a
        # byte boundary: the client can decode everything written so far.
        def flush : Nil
          @is_decided = true
          compressor = @compressor
          return @io.flush unless compressor

          compressor.flush
        end

        def close : Nil
          return if @closed
          @closed = true
          compressor = @compressor
          compressor.close if compressor
          @io.close
        end

        def closed? : Bool
          @closed
        end

        private def choose_encoding : Nil
          @is_decided = true
          response = @context.response
          return if response.headers.has_key?("Content-Encoding")

          request_headers = @context.request.headers
          if request_headers.includes_word?("Accept-Encoding", "gzip")
            # No header fields: the modification time is 0 ("no time stamp",
            # RFC 1952), so the same body always compresses to the same bytes.
            @compressor = Amber::Mica::Gzip::Writer.new(@io, level: @level)
            response.headers["Content-Encoding"] = "gzip"
          elsif request_headers.includes_word?("Accept-Encoding", "deflate")
            @compressor = if ZLIB_FRAMED_DEFLATE
                            Amber::Mica::Zlib::Writer.new(@io, level: @level)
                          else
                            Amber::Mica::Deflate::Writer.new(@io, level: @level)
                          end
            response.headers["Content-Encoding"] = "deflate"
          else
            return
          end
          response.headers.delete("Content-Length")
        end
      end
    end
  end
end
