module Amber::Mica::Deflate
  # The streaming writer shared by `Deflate::Writer`, `Zlib::Writer` and
  # `Gzip::Writer`: an `IO` that encodes what is written to it and writes
  # the stream to its destination.
  #
  # :nodoc:
  abstract class StreamWriter < IO
    # Whether `close` also closes the destination.
    property? sync_close : Bool

    # Returns true once closed.
    getter? closed : Bool = false

    @destination : IO
    @deflater : Deflater

    def initialize(@destination : IO, format : Format, level : Int32, dictionary : Bytes?, header : Gzip::Header?,
                   @sync_close : Bool)
      # A writer dropped unclosed has its tables freed by the guard, which
      # the collector can finalize even when *destination* refers back to
      # this writer.
      @deflater = Deflater.new(format, level, @destination, dictionary, header,
        release_guard: Deflater::ReleaseGuard.new)
    end

    # Raises `IO::Error`: the writer is write-only.
    def read(slice : Bytes) : NoReturn
      raise IO::Error.new("Can't read from #{self.class}")
    end

    # Encodes *slice*. The destination receives output as blocks fill, so
    # bytes written here reach it after a later write, `flush` or `close`.
    def write(slice : Bytes) : Nil
      check_open
      @deflater.write(slice)
    end

    # Writes everything encoded so far to the destination, ending on a byte
    # boundary, and flushes the destination: a decoder that has read the
    # output up to here can decode every byte written before the call
    # (zlib's Z_SYNC_FLUSH). A flush with nothing written since the last
    # one adds no bytes.
    def flush : Nil
      return if @closed
      @deflater.flush
      @destination.flush
    end

    # A `flush` that also drops the history, so the bytes written after it
    # can be decoded without the bytes before it (zlib's Z_FULL_FLUSH).
    def full_flush : Nil
      return if @closed
      @deflater.flush(is_full: true)
      @destination.flush
    end

    # Finishes the stream (the final block and the trailer), flushes the
    # destination and, with `sync_close?`, closes it.
    def close : Nil
      return if @closed
      @closed = true
      @deflater.finish
      @destination.flush
      @destination.close if @sync_close
    end
  end

  # Encodes a raw DEFLATE stream (RFC 1951) as it is written. With
  # *dictionary* the stream starts from that preset dictionary (its last
  # 32 KiB), which the decoder needs too.
  #
  # ```
  # writer = Amber::Mica::Deflate::Writer.new(io, level: 6)
  # writer.write(body)
  # writer.close
  # ```
  class Writer < StreamWriter
    def initialize(io : IO, *, level : Int32 = 6, sync_close : Bool = false, dictionary : Bytes? = nil)
      super(io, Format::Raw, level, dictionary, nil, sync_close)
    end
  end
end
