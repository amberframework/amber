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

  # Raised when bytes handed in as a public key do not encode a point of the
  # curve, or encode one the algorithm refuses (the point at infinity, a
  # coordinate not below the field prime).
  class InvalidPublicKey < Error
  end

  # Raised when bytes handed in as a private key are out of range for the
  # curve (zero, or not below the group order).
  class InvalidPrivateKey < Error
  end

  # Raised when an RSA modulus is outside the sizes Beryl accepts: 2,048 to
  # 8,192 bits for a public key, 2,048 to 4,096 bits for a private key.
  class KeySizeNotSupported < Error
  end

  # Raised when an RSA public exponent is even, below 3 or above 2^32 - 1.
  class PublicExponentNotSupported < Error
  end

  # Raised when the components of an RSA private key do not belong
  # together: the primes are not odd, their product is not the modulus, an
  # exponent or the coefficient is out of range, or a test operation with
  # the key does not invert under the public exponent.
  class MalformedPrivateKey < Error
  end

  # Raised when the result of an RSA private-key operation, raised to the
  # public exponent, does not give back the input. A fault in the
  # computation (a glitch, a flipped bit in memory) would otherwise release
  # a value from which the primes can be computed, so nothing is released.
  class FaultInPrivateKeyOperation < Error
  end

  # Raised when a message is longer than an RSA key can encrypt with OAEP:
  # the modulus size less twice the hash size less 2 bytes (RFC 8017 §7.1.1).
  class MessageTooLongForModulus < Error
  end

  # Raised when a PSS salt is too long for the modulus and hash: the
  # encoded message must hold the hash, the salt and 2 more bytes
  # (RFC 8017 §9.1.1).
  class SaltTooLongForModulus < Error
  end
end
