module Amber::Mica::Deflate
  # The streaming reader shared by `Deflate::Reader`, `Zlib::Reader` and
  # `Gzip::Reader`: an `IO` that decodes its source as it is read.
  #
  # :nodoc:
  abstract class StreamReader < IO
    # Whether `close` also closes the source.
    property? sync_close : Bool

    # Returns true once closed.
    getter? closed : Bool = false

    @source : IO
    # The decoder, until the stream ends or the reader is closed; it then
    # goes back to `Inflater` for the next decode.
    @inflater : Inflater?
    @produced : Int64 = 0_i64

    def initialize(@source : IO, format : Format, limits : DecodeLimits, timeout : Time::Span?, dictionary : Bytes?,
                   @sync_close : Bool, list_of_headers : Array(Gzip::Header)? = nil)
      @inflater = Inflater.acquire(@source, format, limits, timeout, dictionary, list_of_headers)
    end

    # Reads decoded bytes into *slice*; returns 0 at the end of the stream,
    # after every check value has passed.
    def read(slice : Bytes) : Int32
      check_open
      return 0 if slice.empty?
      inflater = @inflater
      return 0 unless inflater
      loop do
        pending = inflater.pending
        unless pending.empty?
          count = Math.min(pending.size, slice.size)
          slice.copy_from(pending.to_unsafe, count)
          inflater.take(count)
          return count
        end
        if slice.size >= Inflater::DIRECT_READ
          # A large slice is decoded into directly.
          count = inflater.produce_into(slice)
          release_inflater if count == 0
          return count
        end
        unless inflater.produce
          release_inflater
          return 0
        end
      end
    end

    # Raises `IO::Error`: the reader is read-only.
    def write(slice : Bytes) : NoReturn
      raise IO::Error.new("Can't write to #{self.class}")
    end

    # Decoded bytes so far.
    def produced : Int64
      inflater = @inflater
      inflater ? inflater.produced : @produced
    end

    def close : Nil
      return if @closed
      @closed = true
      release_inflater
      @source.close if @sync_close
    end

    private def release_inflater : Nil
      inflater = @inflater
      return unless inflater
      @produced = inflater.produced
      @inflater = nil
      inflater.release
    end
  end

  # Decodes a raw DEFLATE stream (RFC 1951) as it is read.
  #
  # ```
  # reader = Amber::Mica::Deflate::Reader.new(io, limits: Amber::Mica::Deflate::DecodeLimits::REQUEST_BODY, timeout: 2.seconds)
  # body = reader.gets_to_end
  # ```
  class Reader < StreamReader
    def initialize(io : IO, *, limits : DecodeLimits, timeout : Time::Span?, sync_close : Bool = false)
      super(io, Format::Raw, limits, timeout, nil, sync_close)
    end
  end
end
