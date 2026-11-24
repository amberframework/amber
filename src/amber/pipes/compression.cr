require "../vendor/mica/deflate"
require "../vendor/mica/brotli"

module Amber
  module Pipe
    # Compresses a pipeline's responses with Brotli, gzip or deflate, whichever
    # the client accepts best (RFC 9110, section 12.5.3: q-values are honored,
    # and on a tie Brotli comes first, then gzip, then deflate).
    #
    # The compressors are Mica's Brotli and DEFLATE encoders in Crystal (a
    # pinned copy under `Amber::Mica`, see
    # `src/amber/vendor/MICA_VENDORED.json`), so the pipe compresses the same
    # way in a program built with `-Dwithout_zlib`, and links no libz and no
    # libbrotlienc. Each response's DEFLATE encoder keeps its tables (about
    # 270 KB) in `malloc` memory, outside the garbage-collected heap, and
    # frees them when the response closes.
    #
    # A body shorter than 1,024 bytes is sent without a content coding, and
    # a response that already has a `Content-Encoding` passes through.
    #
    # A request with a `Range` header is answered uncompressed, because a
    # byte range refers to the uncompressed body. Every response through the
    # pipe carries `Vary: Accept-Encoding`. A response that already has a
    # `Content-Encoding` (for example a pre-gzipped page from the page cache)
    # passes through unchanged.
    #
    # ```
    # pipeline :web do
    #   plug Amber::Pipe::Compression.new
    #   plug Amber::Pipe::Error.new
    # end
    # ```
    #
    # *level* is the gzip and deflate level, from 0 (stored, no compression)
    # through 1 (fastest) to 9 (smallest); -1 selects the default, 6.
    # *brotli_quality* is the Brotli quality, 0 to 11 (default 5, the
    # quality the Brotli authors suggest for dynamic responses), or nil to
    # offer gzip and deflate only.
    class Compression < Base
      # The level -1 selects.
      DEFAULT_LEVEL = 6
      # The Brotli quality used unless another is given.
      DEFAULT_BROTLI_QUALITY = 5

      # The level every gzip or deflate response is compressed at, 0 to 9.
      getter level : Int32
      # The quality every Brotli response is compressed at, 0 to 11, or nil
      # when Brotli is not offered.
      getter brotli_quality : Int32?

      def initialize(level : Int32 = -1, brotli_quality : Int32? = DEFAULT_BROTLI_QUALITY)
        unless -1 <= level <= 9
          raise ArgumentError.new("Compression level must be in -1..9, got #{level}")
        end
        if quality = brotli_quality
          unless 0 <= quality <= 11
            raise ArgumentError.new("Brotli quality must be in 0..11, got #{quality}")
          end
        end
        @level = level == -1 ? DEFAULT_LEVEL : level
        @brotli_quality = brotli_quality
      end

      def call(context : HTTP::Server::Context)
        return call_next(context) if context.request.headers.has_key?("Range")
        context.response.headers.add("Vary", "Accept-Encoding")
        context.response.output = CompressedOutput.new(context.response.output, context, @level, @brotli_quality)
        call_next(context)
      end
    end
  end
end
