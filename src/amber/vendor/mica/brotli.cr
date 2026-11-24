require "./core"

# Brotli (RFC 7932) in pure Crystal: no libbrotlidec, no libbrotlienc.
#
# `encode` and `Writer` compress at qualities 0 to 11 (see docs/brotli.md).
#
# Every decode takes required `limits:` (`DecodeLimits`: output, ratio,
# window, metadata and work) and a required `timeout:` (a `Time::Span`, or
# nil for none), and raises a typed error before the output a limit
# guards is produced, so a decompression bomb costs bounded memory and
# time.
#
# ```
# limits = Amber::Mica::Brotli::DecodeLimits::REQUEST_BODY
# Amber::Mica::Brotli.decode(body, limits: limits, timeout: 2.seconds)
# ```
module Amber::Mica::Brotli
  # Decodes the Brotli stream *input* in one call. The stream must end
  # with its last metablock, zero padding bits, and nothing after it.
  def self.decode(input : Bytes, *, limits : DecodeLimits, timeout : Time::Span?) : Bytes
    Decoder.decode(input, limits, timeout)
  end

  # Encodes *input* as one Brotli stream. *quality* (0 to 11) trades speed
  # for size; *window_bits* (10 to 24) sets how far back matches reach,
  # (1 << window_bits) - 16 bytes. The same input and options always give
  # the same bytes. Raises `ArgumentError` for a quality or window outside
  # those ranges.
  #
  # ```
  # compressed = Amber::Mica::Brotli.encode(body, quality: 5)
  # ```
  def self.encode(input : Bytes, *, quality : Int32 = 5, window_bits : Int32 = 22) : Bytes
    Encoder.encode(input, quality, window_bits)
  end
end

require "./brotli/errors"
require "./brotli/decode_limits"
require "./brotli/dictionary"
require "./brotli/tables"
require "./brotli/prefix_code"
require "./brotli/decoder"
require "./brotli/reader"
require "./brotli/bit_writer"
require "./brotli/huffman_builder"
require "./brotli/huffman_code"
require "./brotli/encoder_codes"
require "./brotli/match_finder"
require "./brotli/dictionary_matcher"
require "./brotli/block_splitter"
require "./brotli/metablock_writer"
require "./brotli/classic_encoder"
require "./brotli/encode/common"
require "./brotli/encode/hasher"
require "./brotli/encode/longest_match_hasher"
require "./brotli/encode/backward_references"
require "./brotli/encode/entropy_encode"
require "./brotli/encode/arena"
require "./brotli/encode/metablock"
require "./brotli/encode/metablock_store"
require "./brotli/encode/literal_cost"
require "./brotli/encode/cluster"
require "./brotli/encode/block_splitter"
require "./brotli/encode/static_dictionary"
require "./brotli/encode/zopfli"
require "./brotli/encoder"
require "./brotli/writer"
