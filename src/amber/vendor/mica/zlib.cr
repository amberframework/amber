require "./deflate"

# zlib streams (RFC 1950): a two-byte header, DEFLATE data and an Adler-32
# of the output. The decoder checks the header (FCHECK, compression
# method 8, CINFO at most 7 and within `max_window_bytes`), a preset
# dictionary's id when FDICT is set, and the Adler-32.
#
# ```
# Amber::Mica::Zlib.decode(bytes, limits: Amber::Mica::Deflate::DecodeLimits::REQUEST_BODY, timeout: nil)
# ```
module Amber::Mica::Zlib
  # Decodes the zlib stream *input* in one call. *dictionary* is the
  # preset dictionary a stream with FDICT needs (its Adler-32 must match
  # the stream's DICTID). Nothing may follow the Adler-32.
  def self.decode(input : Bytes, *, limits : Deflate::DecodeLimits, timeout : Time::Span?,
                  dictionary : Bytes? = nil) : Bytes
    Deflate::Inflater.decode(input, Deflate::Format::Zlib, limits, timeout, dictionary)
  end

  # Encodes *input* as a zlib stream in one call, at *level* 0 to 9. With
  # *dictionary* the stream starts from that preset dictionary (its last
  # 32 KiB) and its header carries FDICT and the dictionary's Adler-32; the
  # decoder needs the same dictionary.
  #
  # ```
  # Amber::Mica::Zlib.encode(body, level: 6)
  # ```
  def self.encode(input : Bytes, *, level : Int32 = 6, dictionary : Bytes? = nil) : Bytes
    Deflate::Deflater.encode(input, Deflate::Format::Zlib, level, dictionary)
  end

  # Decodes a zlib stream as it is read.
  class Reader < Deflate::StreamReader
    def initialize(io : IO, *, limits : Deflate::DecodeLimits, timeout : Time::Span?, dictionary : Bytes? = nil,
                   sync_close : Bool = false)
      super(io, Deflate::Format::Zlib, limits, timeout, dictionary, sync_close)
    end
  end

  # Encodes a zlib stream as it is written.
  #
  # ```
  # writer = Amber::Mica::Zlib::Writer.new(io, level: 6)
  # writer.write(body)
  # writer.close
  # ```
  class Writer < Deflate::StreamWriter
    def initialize(io : IO, *, level : Int32 = 6, dictionary : Bytes? = nil, sync_close : Bool = false)
      super(io, Deflate::Format::Zlib, level, dictionary, nil, sync_close)
    end
  end
end
