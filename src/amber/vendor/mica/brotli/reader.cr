module Amber::Mica::Brotli
  # Decodes a Brotli stream (RFC 7932) as it is read.
  #
  # ```
  # reader = Amber::Mica::Brotli::Reader.new(io, limits: Amber::Mica::Brotli::DecodeLimits::REQUEST_BODY, timeout: 2.seconds)
  # body = reader.gets_to_end
  # ```
  #
  # The reader reads ahead from its source, so give it an IO that holds
  # only the compressed stream; a byte after the stream's end raises
  # `MalformedStreamError`.
  class Reader < IO
    # Whether `close` also closes the source.
    property? sync_close : Bool

    # Returns true once closed.
    getter? closed : Bool = false

    @source : IO
    @brotli_decoder : Brotli::Decoder?
    @more : Bool = true
    @produced : Int64 = 0_i64

    def initialize(@source : IO, *, limits : DecodeLimits, timeout : Time::Span?, @sync_close : Bool = false)
      @brotli_decoder = Brotli::Decoder.acquire(@source, nil, limits, timeout)
    end

    # Reads decoded bytes into *slice*; returns 0 at the end of the stream.
    def read(slice : Bytes) : Int32
      check_open
      return 0 if slice.empty?
      decoder = @brotli_decoder
      return 0 unless decoder
      loop do
        pending = decoder.pending
        unless pending.empty?
          count = Math.min(pending.size, slice.size)
          slice.copy_from(pending.to_unsafe, count)
          decoder.take(count)
          return count
        end
        unless @more
          release_decoder
          return 0
        end
        @more = decoder.produce
      end
    end

    # Raises `IO::Error`: the reader is read-only.
    def write(slice : Bytes) : NoReturn
      raise IO::Error.new("Can't write to #{self.class}")
    end

    # Decoded bytes so far.
    def produced : Int64
      decoder = @brotli_decoder
      decoder ? decoder.produced : @produced
    end

    def close : Nil
      return if @closed
      @closed = true
      release_decoder
      @source.close if @sync_close
    end

    private def release_decoder : Nil
      decoder = @brotli_decoder
      return unless decoder
      @produced = decoder.produced
      @brotli_decoder = nil
      decoder.release
    end
  end
end
