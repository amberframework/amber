module Amber
  module Pipe
    class Compression < Base
      # The response output while `Compression` is in the pipeline. It holds
      # back the first `MINIMUM_COMPRESSED_BYTES` of the body; once that much
      # is written (or the action flushes) it decides (see
      # `ContentCoding.choose`) whether to send Brotli, gzip or deflate, or
      # pass the body through, and builds a compressor only when it
      # compresses. A body that closes shorter than that is sent as it is:
      # compressing it would save little and cost a compressor's setup.
      #
      # :nodoc:
      class CompressedOutput < IO
        # Whether `Content-Encoding: deflate` carries a zlib stream (a
        # two-byte header and an Adler-32 trailer around the DEFLATE data),
        # as RFC 9110 defines it. `HTTP::CompressHandler` writes that from
        # Crystal 1.22.0 on and bare DEFLATE data before, and this pipe
        # follows the compiler it is built with.
        ZLIB_FRAMED_DEFLATE = {{ compare_versions(Crystal::VERSION, "1.22.0") >= 0 }}

        # The codings offered, in the server's order of preference.
        OFFERED_WITH_BROTLI    = ["br", "gzip", "deflate"]
        OFFERED_WITHOUT_BROTLI = ["gzip", "deflate"]

        # A body shorter than this is sent without a content coding.
        MINIMUM_COMPRESSED_BYTES = 1_024

        # Nil until the first write or flush decides the content coding, and
        # nil from then on for a body that passes through uncompressed.
        @compressor : Amber::Mica::Deflate::StreamWriter | Amber::Mica::Brotli::Writer | Nil
        @is_decided = false
        # The start of the body, held until the coding is decided: the
        # first `@held_size` bytes of `@held_back` (allocated on first use).
        @held_back = Bytes.empty
        @held_size = 0
        @closed = false

        def initialize(@io : IO, @context : HTTP::Server::Context, @level : Int32, @brotli_quality : Int32?)
        end

        def read(slice : Bytes) : NoReturn
          raise NotImplementedError.new("read")
        end

        def write(slice : Bytes) : Nil
          raise IO::Error.new("Closed stream") if @closed
          unless @is_decided
            return hold_back(slice) if @held_size + slice.size < MINIMUM_COMPRESSED_BYTES

            choose_encoding
            release_held_back
          end
          compressor = @compressor
          return @io.write(slice) unless compressor

          compressor.write(slice)
        end

        # A flush before the first write sends the headers uncompressed, so
        # the body that follows stays uncompressed too, as with
        # `HTTP::CompressHandler`. A flush after a write decides the coding
        # then, however short the body so far. A flush of a compressed body
        # ends on a byte boundary: the client can decode everything written
        # so far.
        def flush : Nil
          unless @is_decided
            if @held_size == 0
              @is_decided = true
            else
              choose_encoding
              release_held_back
            end
          end
          compressor = @compressor
          return @io.flush unless compressor

          compressor.flush
        end

        def close : Nil
          return if @closed
          @closed = true
          # Still undecided: the whole body is shorter than the minimum.
          unless @is_decided
            @is_decided = true
            release_held_back
          end
          compressor = @compressor
          compressor.close if compressor
          @io.close
        end

        def closed? : Bool
          @closed
        end

        private def hold_back(slice : Bytes) : Nil
          @held_back = Bytes.new(MINIMUM_COMPRESSED_BYTES) if @held_back.empty?
          (@held_back + @held_size).copy_from(slice)
          @held_size += slice.size
        end

        # Writes the held-back start of the body through the chosen coding.
        private def release_held_back : Nil
          return if @held_size == 0

          held_back = @held_back[0, @held_size]
          @held_size = 0
          compressor = @compressor
          if compressor
            compressor.write(held_back)
          else
            @io.write(held_back)
          end
        end

        private def choose_encoding : Nil
          @is_decided = true
          response = @context.response
          return if response.headers.has_key?("Content-Encoding")

          brotli_quality = @brotli_quality
          list_of_offered = brotli_quality ? OFFERED_WITH_BROTLI : OFFERED_WITHOUT_BROTLI
          case ContentCoding.choose(@context.request.headers, list_of_offered)
          when "br"
            @compressor = Amber::Mica::Brotli::Writer.new(@io, quality: brotli_quality || DEFAULT_BROTLI_QUALITY)
            response.headers["Content-Encoding"] = "br"
          when "gzip"
            # No header fields: the modification time is 0 ("no time stamp",
            # RFC 1952), so the same body always compresses to the same bytes.
            @compressor = Amber::Mica::Gzip::Writer.new(@io, level: @level)
            response.headers["Content-Encoding"] = "gzip"
          when "deflate"
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
