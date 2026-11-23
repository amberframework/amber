require "../error"

module Amber::Beryl::Crypto
  # The base of every error raised by `Amber::Beryl::Crypto`.
  class Error < Amber::Beryl::Error
  end

  # Raised when a key derivation is asked for more bytes than its standard
  # allows, for example more than 255 hash outputs from HKDF (RFC 5869 §2.3).
  class DerivedKeyTooLong < Error
  end

  # Raised when a key derivation is asked for a negative number of bytes.
  class DerivedKeySizeIsNegative < Error
  end

  # Raised when PBKDF2 is asked to run fewer than one iteration.
  class IterationCountTooSmall < Error
  end

  # Raised when a message grows past the length its hash function can encode
  # (2^61 - 1 bytes for the hashes in this shard).
  class MessageTooLong < Error
  end

  # Raised when the buffer handed to `Digest#final` is a different size than
  # the digest or the authentication tag being written.
  class OutputSizeMismatch < Error
  end

  # Raised when a truncated authentication tag is shorter than RFC 2104 §5
  # allows: half the hash output, and never under 80 bits.
  class TruncatedTagTooShort < Error
  end

  # Raised when a key is a different size than its cipher takes, for example
  # anything but 32 bytes for ChaCha20-Poly1305.
  class KeySizeMismatch < Error
  end

  # Raised when a nonce or an initialization vector is a different size than
  # its cipher takes.
  class NonceSizeMismatch < Error
  end

  # Raised when an authenticated cipher is asked for a tag size its standard
  # does not define.
  class TagSizeNotSupported < Error
  end

  # Raised when code written for a processor's instructions is reached on a
  # processor without them. `ProcessorFeatures` decides which code runs, so
  # this means a fault in Beryl, not in the caller.
  class UnsupportedProcessor < Error
  end
end
