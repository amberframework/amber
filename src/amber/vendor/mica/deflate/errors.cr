module Amber::Mica::Deflate
  # Raised when a compressed stream breaks RFC 1950, 1951 or 1952: an
  # invalid block type or Huffman code, a back reference before the start
  # of the output, a bad header or trailer. `byte_offset` is the 0-based
  # byte of the compressed input where the problem was found.
  class MalformedStreamError < Amber::Mica::ParseError
  end

  # Raised when the input ends inside a stream (a block, a header or a
  # trailer).
  class TruncatedStreamError < MalformedStreamError
  end

  # Raised when a check value does not match the decoded data: Adler-32
  # (zlib), CRC-32 or ISIZE (gzip), the gzip header CRC (FHCRC), or a zlib
  # preset dictionary's id.
  class ChecksumError < MalformedStreamError
  end

  # Raised when a decode would pass one of its `DecodeLimits`. `limit` names
  # it: "max_output_bytes", "max_ratio", "max_window_bytes", "max_members"
  # or "max_metadata_bytes". The work budget and the timeout raise
  # `Amber::Mica::WorkBudgetExceededError` and `Amber::Mica::DeadlineExceededError`.
  class DecodeLimitError < Amber::Mica::LimitExceededError
    # The name of the limit, for example "max_output_bytes".
    getter limit : String

    def initialize(detail : String, position : Core::Position, @limit : String)
      super(detail, position)
    end
  end
end
