module Amber::Mica::Brotli
  # Raised when a stream breaks RFC 7932: a bad window size, metablock
  # header, prefix code, context map or distance, nonzero padding, a
  # command that runs past its metablock, or bytes after the last
  # metablock. `byte_offset` is the 0-based byte of the compressed input
  # where the problem was found.
  class MalformedStreamError < Amber::Mica::ParseError
  end

  # Raised when the input ends inside a stream.
  class TruncatedStreamError < MalformedStreamError
  end

  # Raised when a decode would pass one of its `DecodeLimits`. `limit`
  # names it: "max_output_bytes", "max_ratio", "max_window_bytes" or
  # "max_metadata_bytes". The work budget and the timeout raise
  # `Amber::Mica::WorkBudgetExceededError` and `Amber::Mica::DeadlineExceededError`.
  class DecodeLimitError < Amber::Mica::LimitExceededError
    # The name of the limit, for example "max_output_bytes".
    getter limit : String

    def initialize(detail : String, position : Core::Position, @limit : String)
      super(detail, position)
    end
  end
end
