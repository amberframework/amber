{% unless flag?(:without_zlib) %}
  require "compress/deflate"
  require "compress/gzip"
{% end %}

module Amber
  module Pipe
    # Gzips or deflates a pipeline's responses for clients that accept it.
    #
    # The bytes on the wire match Crystal's `HTTP::CompressHandler` at the same
    # level. The difference is where the compressor lives: each zlib stream
    # (about 270 KB of state and buffers) comes from `malloc`, outside the
    # garbage-collected heap, and goes back to a small pool when the response
    # closes. `HTTP::CompressHandler` allocates that state from the collected
    # heap for every response, which made it the largest allocation in a
    # generated app.
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
    # *level* is the zlib level, 0 to 9, or -1 for zlib's default (6).
    # *idle_compressors* is how many compressors the pool keeps between
    # responses; one more in use at once is created and then released.
    class Compression < Base
      # How many compressors the pool keeps between responses by default.
      DEFAULT_IDLE_COMPRESSORS = 4

      {% if flag?(:without_zlib) %}
        def initialize(level : Int32 = -1, idle_compressors : Int32 = DEFAULT_IDLE_COMPRESSORS)
        end

        def call(context : HTTP::Server::Context)
          call_next(context)
        end
      {% else %}
        # The compressors this pipe lends to its responses.
        getter pool : DeflaterPool

        def initialize(level : Int32 = ::Compress::Deflate::DEFAULT_COMPRESSION,
                       idle_compressors : Int32 = DEFAULT_IDLE_COMPRESSORS)
          unless -1 <= level <= 9
            raise ArgumentError.new("Compression level must be in -1..9, got #{level}")
          end
          if idle_compressors < 0
            raise ArgumentError.new("idle_compressors must be 0 or more, got #{idle_compressors}")
          end
          @pool = DeflaterPool.new(level, idle_compressors)
        end

        def call(context : HTTP::Server::Context)
          return call_next(context) if context.request.headers.has_key?("Range")
          context.response.headers.add("Vary", "Accept-Encoding")
          context.response.output = CompressedOutput.new(context.response.output, context, @pool)
          call_next(context)
        end
      {% end %}
    end
  end
end
