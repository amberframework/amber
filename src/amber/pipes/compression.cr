require "../vendor/mica/deflate"

module Amber
  module Pipe
    # Gzips or deflates a pipeline's responses for clients that accept it.
    #
    # The compressor is Mica's DEFLATE encoder in Crystal (a pinned copy under
    # `Amber::Mica`, see `src/amber/vendor/MICA_VENDORED.json`), so the pipe
    # compresses the same way in a program built with `-Dwithout_zlib`, which
    # links no libz. Each response's encoder keeps its tables (about 270 KB)
    # in `malloc` memory, outside the garbage-collected heap, and frees them
    # when the response closes.
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
    # *level* runs from 0 (stored, no compression) through 1 (fastest) to 9
    # (smallest); -1 selects the default, 6.
    class Compression < Base
      # The level -1 selects.
      DEFAULT_LEVEL = 6

      # The level every response is compressed at, 0 to 9.
      getter level : Int32

      def initialize(level : Int32 = -1)
        unless -1 <= level <= 9
          raise ArgumentError.new("Compression level must be in -1..9, got #{level}")
        end
        @level = level == -1 ? DEFAULT_LEVEL : level
      end

      def call(context : HTTP::Server::Context)
        return call_next(context) if context.request.headers.has_key?("Range")
        context.response.headers.add("Vary", "Accept-Encoding")
        context.response.output = CompressedOutput.new(context.response.output, context, @level)
        call_next(context)
      end
    end
  end
end
