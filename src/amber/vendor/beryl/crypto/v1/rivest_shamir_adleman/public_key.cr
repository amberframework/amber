module Amber::Beryl::Crypto::V1::RivestShamirAdleman
  # An RSA public key: a modulus of 2,048 to 8,192 bits and an odd public
  # exponent from 3 to 2^32 - 1. It verifies signatures and encrypts.
  #
  # ```
  # public_key = Amber::Beryl::Crypto::V1::RSA::PublicKey.new(modulus_bytes, 65_537)
  # public_key.verify_pkcs1_signature(message, signature, hash_function: Amber::Beryl::Crypto::V1::SHA256) # => true or false
  # ```
  #
  # Everything a public key does is public, so its operations may take time
  # that depends on their inputs.
  class PublicKey
    SMALLEST_MODULUS_BIT_COUNT =           2_048
    LARGEST_MODULUS_BIT_COUNT  =           8_192
    SMALLEST_PUBLIC_EXPONENT   =           3_u64
    LARGEST_PUBLIC_EXPONENT    = 0xffff_ffff_u64

    # The public exponent.
    getter public_exponent : UInt64

    # The modulus as words, read and checked when the key is built; the
    # Montgomery constants (`OddModulus`) are computed on the first
    # operation, so a key read and never used (a certificate's, passed
    # along) costs only the reading.
    @modulus_words : Slice(UInt64)
    @modulus_bit_count : Int32
    @modulus : OddModulus?

    # R^e mod n, computed on the second operation: it costs about one
    # operation and saves a multiplication in each one after.
    @public_exponent_correction : Slice(UInt64)?
    @has_operated = false

    # Takes the big-endian *modulus* (leading zero bytes allowed) and the
    # public exponent, as big-endian bytes or as an integer. Raises
    # `KeySizeNotSupported` or `PublicExponentNotSupported` when either is
    # outside the ranges above, or when the modulus is even.
    def initialize(modulus : Bytes, public_exponent : Bytes | Int)
      @modulus_words, @modulus_bit_count = PublicKey.read_modulus_words(modulus, SMALLEST_MODULUS_BIT_COUNT, LARGEST_MODULUS_BIT_COUNT)
      @public_exponent = PublicKey.read_public_exponent(public_exponent)
    end

    # :nodoc:
    #
    # The modulus with its Montgomery constants, built on first use. Two
    # fibers building it at once each build the same value.
    def modulus : OddModulus
      if built = @modulus
        return built
      end
      @modulus = OddModulus.new(@modulus_words, @modulus_bit_count)
    end

    # :nodoc:
    #
    # Reads and checks a modulus. Its size and its low bit are public, and
    # pass through `Declassification.reveal` so the constant-time checks
    # know it.
    def self.read_modulus(bytes : Bytes, smallest_bit_count : Int32, largest_bit_count : Int32) : OddModulus
      words, bit_count = read_modulus_words(bytes, smallest_bit_count, largest_bit_count)
      OddModulus.new(words, bit_count)
    end

    # :nodoc:
    #
    # `read_modulus` without the Montgomery constants: the modulus's words
    # and bit length, checked.
    def self.read_modulus_words(bytes : Bytes, smallest_bit_count : Int32, largest_bit_count : Int32) : {Slice(UInt64), Int32}
      if bytes.size > largest_bit_count // 8 + 1
        raise KeySizeNotSupported.new("the modulus takes #{bytes.size} bytes; the largest Beryl accepts here is #{largest_bit_count} bits")
      end
      words, bit_count = OddModulus.words_from_bytes(bytes)
      unless smallest_bit_count <= bit_count <= largest_bit_count
        raise KeySizeNotSupported.new("the modulus has #{bit_count} bits; Beryl accepts #{smallest_bit_count} to #{largest_bit_count} here")
      end
      unless Declassification.reveal(words[0] & 1_u64) == 1_u64
        raise KeySizeNotSupported.new("the modulus is even, so it is not an RSA modulus")
      end
      {words, bit_count}
    end

    # :nodoc:
    def self.read_public_exponent(bytes : Bytes) : UInt64
      words = Slice(UInt64).new(1)
      fits = Declassification.reveal(MontgomeryArithmetic.decode_big_endian(bytes, words))
      raise PublicExponentNotSupported.new("the public exponent is longer than 64 bits") unless fits == 1_u64
      read_public_exponent(Declassification.reveal(words[0]))
    end

    # :nodoc:
    def self.read_public_exponent(value : Int) : UInt64
      unless SMALLEST_PUBLIC_EXPONENT <= value <= LARGEST_PUBLIC_EXPONENT && value.odd?
        raise PublicExponentNotSupported.new("the public exponent is #{value}; Beryl accepts odd values from 3 to 2^32 - 1")
      end
      value.to_u64
    end

    # The size of the modulus in bits.
    def modulus_bit_count : Int32
      @modulus_bit_count
    end

    # The size of a signature or a ciphertext under this key, in bytes.
    def modulus_bytesize : Int32
      (@modulus_bit_count + 7) // 8
    end

    # Returns whether *signature* is a PKCS #1 v1.5 signature (RFC 8017
    # §8.2) of *message* hashed with *hash_function*: one of
    # `Compatibility::SHA1`, `SHA224`, `SHA256`, `SHA384`, `SHA512`,
    # `SHA512_256`. The expected encoding is built and compared whole, so
    # only the one exact encoding is accepted. Never raises for a malformed
    # signature.
    def verify_pkcs1_signature(message : Bytes | String, signature : Bytes, *, hash_function : D.class) : Bool forall D
      prefix = MessageEncoding.verification_digest_info_prefix(hash_function)
      encoded = apply_public_exponent(signature)
      return false unless encoded

      encoded == MessageEncoding.encode_pkcs1(prefix, D.digest(message), modulus_bytesize)
    end

    # Returns whether *signature* is a PSS signature (RFC 8017 §8.1) of
    # *message*, with *hash_function* (a SHA-2 hash) for the message and
    # for MGF1, and a salt of *salt_bytesize* bytes. Never raises for a
    # malformed signature.
    def verify_pss_signature(message : Bytes | String, signature : Bytes, *, hash_function : D.class,
                             salt_bytesize : Int32) : Bool forall D
      MessageEncoding.ensure_secure_hash_2(hash_function)
      encoded_with_leading_byte = apply_public_exponent(signature)
      return false unless encoded_with_leading_byte

      encoded_bit_count = modulus_bit_count - 1
      encoded_bytesize = (encoded_bit_count + 7) // 8
      leading_bytesize = modulus_bytesize - encoded_bytesize
      return false unless encoded_with_leading_byte[0, leading_bytesize].all?(&.zero?)

      MessageEncoding.pss_encoding_matches?(hash_function, D.digest(message),
        encoded_with_leading_byte[leading_bytesize, encoded_bytesize], encoded_bit_count, salt_bytesize)
    end

    # Returns *message* encrypted with RSAES-OAEP (RFC 8017 §7.1.1), with
    # *hash_function* for the label and for MGF1 (`Compatibility::SHA1` or
    # a SHA-2 hash) and an optional *label*. Raises
    # `MessageTooLongForModulus` when the message is longer than the
    # modulus size less twice the hash size less 2 bytes.
    def encrypt_with_oaep(message : Bytes | String, *, hash_function : D.class, label : Bytes | String = Bytes.empty) : Bytes forall D
      seed = Random::Secure.random_bytes(D::DIGEST_SIZE)
      encrypt_with_oaep_using_seed(message.to_slice, seed, hash_function: hash_function, label: label.to_slice)
    end

    # :nodoc:
    #
    # `encrypt_with_oaep` with a given seed, for tests that must reproduce
    # a ciphertext.
    def encrypt_with_oaep_using_seed(message : Bytes, seed : Bytes, *, hash_function : D.class, label : Bytes) : Bytes forall D
      MessageEncoding.ensure_oaep_hash(hash_function)
      largest_message_bytesize = modulus_bytesize - 2 * D::DIGEST_SIZE - 2
      if message.size > largest_message_bytesize
        raise MessageTooLongForModulus.new("the message has #{message.size} bytes; this key and hash take at most #{largest_message_bytesize}")
      end

      encoded = MessageEncoding.encode_oaep(hash_function, message, D.digest(label), seed, modulus_bytesize)
      apply_public_exponent(encoded) || raise MessageTooLongForModulus.new("the encoded message is not below the modulus")
    end

    # :nodoc:
    #
    # Returns input^e mod n, *modulus_bytesize* bytes, or `nil` when
    # *input* is not that size or is not below the modulus.
    def apply_public_exponent(input : Bytes) : Bytes?
      return nil unless input.size == modulus_bytesize

      input_words = Slice(UInt64).new(@modulus_words.size)
      MontgomeryArithmetic.decode_big_endian(input, input_words)
      return nil unless MontgomeryArithmetic.less_than_bit(input_words, @modulus_words) == 1_u64

      result_words = Slice(UInt64).new(@modulus_words.size)
      if correction = @public_exponent_correction
        modulus.exponentiate_by_public_exponent(result_words, input_words, @public_exponent, correction)
      elsif @has_operated
        correction = modulus.public_exponent_correction(@public_exponent)
        @public_exponent_correction = correction
        modulus.exponentiate_by_public_exponent(result_words, input_words, @public_exponent, correction)
      else
        @has_operated = true
        modulus.exponentiate_by_public_exponent(result_words, input_words, @public_exponent)
      end
      result = Bytes.new(modulus_bytesize)
      MontgomeryArithmetic.encode_big_endian(result_words, result)
      result
    end
  end
end
