require "../error"

module Amber::Beryl::Encoding
  # The base of every error raised while reading an encoding (DER, PEM).
  class Error < Amber::Beryl::Error
  end

  # Raised when bytes are not the strict encoding they claim to be: a length
  # that runs past the input, a non-minimal integer, an indefinite length,
  # a malformed time. The message names the rule and the byte offset.
  class MalformedEncoding < Error
    # The offset, from the start of the input handed to the reader, of the
    # element that broke the rule.
    getter offset : Int32

    def initialize(reason : String, @offset : Int32 = 0)
      super("#{reason} (at byte #{@offset})")
    end
  end

  # Raised when an input goes past a limit set for untrusted data: its size,
  # or how deeply its elements nest.
  class LimitExceeded < Error
  end
end
