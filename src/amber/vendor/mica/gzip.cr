require "./deflate"

# gzip streams (RFC 1952): one or more members, each a header, DEFLATE
# data, a CRC-32 and the size modulo 2^32. The decoder checks the magic
# bytes, compression method 8, the reserved flag bits, the header CRC
# (FHCRC), each member's CRC-32 and size, and `max_members` and
# `max_metadata_bytes`. After a member the input either ends or starts
# another member.
#
# ```
# Amber::Mica::Gzip.decode(bytes, limits: Amber::Mica::Deflate::DecodeLimits::REQUEST_BODY, timeout: nil)
# ```
module Amber::Mica::Gzip
  # One member's header fields. *file_name* and *comment* are the raw
  # bytes (RFC 1952 says ISO 8859-1) without the terminating zero.
  record Header, modification_time : UInt32, extra_flags : UInt8, operating_system : UInt8, is_text : Bool,
    extra_field : Bytes?, file_name : Bytes?, comment : Bytes?

  # Decodes the gzip stream *input* (every member) in one call.
  def self.decode(input : Bytes, *, limits : Deflate::DecodeLimits, timeout : Time::Span?) : Bytes
    Deflate::Inflater.decode(input, Deflate::Format::Gzip, limits, timeout)
  end

  # Encodes *input* as one gzip member in one call, at *level* 0 to 9.
  # *header* supplies the member's header fields (FEXTRA, FNAME and
  # FCOMMENT are written when it has them). Without one the modification
  # time is 0 and the operating system 255 (unknown), so the same input
  # and level always give the same bytes.
  #
  # ```
  # Amber::Mica::Gzip.encode(body, level: 6)
  # ```
  def self.encode(input : Bytes, *, level : Int32 = 6, header : Header? = nil) : Bytes
    Deflate::Deflater.encode(input, Deflate::Format::Gzip, level, nil, header)
  end

  # Encodes one gzip member as it is written.
  #
  # ```
  # writer = Amber::Mica::Gzip::Writer.new(io, level: 6)
  # writer.write(body)
  # writer.close
  # ```
  class Writer < Deflate::StreamWriter
    def initialize(io : IO, *, level : Int32 = 6, header : Header? = nil, sync_close : Bool = false)
      super(io, Deflate::Format::Gzip, level, nil, header, sync_close)
    end
  end

  # Decodes a gzip stream (every member) as it is read.
  class Reader < Deflate::StreamReader
    # The headers of the members read so far.
    getter list_of_headers = [] of Header

    def initialize(io : IO, *, limits : Deflate::DecodeLimits, timeout : Time::Span?, sync_close : Bool = false)
      super(io, Deflate::Format::Gzip, limits, timeout, nil, sync_close, @list_of_headers)
    end
  end
end
