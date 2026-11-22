require "./core"

# DEFLATE decoding in pure Crystal (RFC 1951), the format inside zlib
# (`Amber::Mica::Zlib`, RFC 1950) and gzip (`Amber::Mica::Gzip`, RFC 1952) streams. No
# libz.
#
# Every decode takes required `limits:` (`DecodeLimits`: output, ratio,
# window, members, metadata and work) and a required `timeout:` (a
# `Time::Span`, or nil for none), and raises a typed error before the
# output a limit guards is produced, so a decompression bomb costs bounded
# memory and time.
#
# ```
# limits = Amber::Mica::Deflate::DecodeLimits::REQUEST_BODY
# Amber::Mica::Gzip.decode(body, limits: limits, timeout: 2.seconds)
# ```
module Amber::Mica::Deflate
  # Decodes the raw DEFLATE stream *input* in one call. The stream must
  # end with its final block and nothing may follow it.
  def self.decode(input : Bytes, *, limits : DecodeLimits, timeout : Time::Span?) : Bytes
    Inflater.decode(input, Format::Raw, limits, timeout)
  end

  # Encodes *input* as a raw DEFLATE stream in one call. *level* runs from
  # 0 (stored, no compression) through 1 (fastest) to 9 (smallest); the
  # same input and level always give the same bytes.
  #
  # ```
  # Amber::Mica::Deflate.encode(body, level: 6)
  # ```
  def self.encode(input : Bytes, *, level : Int32 = 6) : Bytes
    Deflater.encode(input, Format::Raw, level)
  end
end

require "./deflate/errors"
require "./deflate/decode_limits"
require "./deflate/checksum"
require "./deflate/huffman_table"
require "./deflate/inflater"
require "./deflate/stream_reader"
require "./deflate/huffman_code_builder"
require "./deflate/block_writer"
require "./deflate/deflater"
require "./deflate/stream_writer"
require "./zlib"
require "./gzip"
