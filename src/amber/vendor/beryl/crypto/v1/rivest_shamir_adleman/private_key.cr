module Amber::Beryl::Crypto::V1::RivestShamirAdleman
  # An RSA private key of two primes, with a modulus of 2,048 to 4,096 bits.
  # It signs and decrypts.
  #
  # ```
  # private_key = Amber::Beryl::Crypto::V1::RSA::PrivateKey.new(
  #   modulus: n, public_exponent: e, private_exponent: d,
  #   first_prime: p, second_prime: q,
  #   first_prime_exponent: d_p, second_prime_exponent: d_q, coefficient: q_inv,
  # )
  # signature = private_key.sign_with_pss("message", hash_function: Amber::Beryl::Crypto::V1::SHA256, salt_bytesize: 32)
  # private_key.public_key.verify_pss_signature("message", signature, hash_function: Amber::Beryl::Crypto::V1::SHA256, salt_bytesize: 32) # => true
  # ```
  #
  # The private operation uses the Chinese remainder theorem (RFC 8017
  # §5.1.2, the second representation), runs in time that does not depend
  # on the key or on the input, and checks its result with the public
  # exponent before releasing it (`FaultInPrivateKeyOperation`). Key
  # generation and keys of more than two primes are not supported; keys
  # come from key files, which a caller parses.
  class PrivateKey
    SMALLEST_MODULUS_BIT_COUNT = 2_048
    LARGEST_MODULUS_BIT_COUNT  = 4_096

    # The input of the test operation run when the key is built.
    KEY_TEST_INPUT = 2_u64

    # The matching public key.
    getter public_key : PublicKey

    # Public values, kept here as integers so that no secret buffer is read
    # to find them.
    @modulus_bytesize : Int32
    @public_exponent : UInt64

    @modulus : OddModulus
    # R^e mod n, so that each private operation's check under the public
    # exponent takes one multiplication fewer.
    @public_exponent_correction : Slice(UInt64)
    # The modulus in the form of the AVX-512 IFMA path, for that check, where
    # the processor and the modulus suit it.
    @modulus_in_digits : MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PublicModulus?
    @first_prime : OddModulus
    @second_prime : OddModulus
    @first_prime_exponent : Bytes
    @second_prime_exponent : Bytes
    @coefficient : Slice(UInt64)
    # The primes in the form of the AVX-512 IFMA path, where the processor
    # and the key suit it (`MontgomeryMultiplicationWithIntegerFusedMultiplyAdd`).
    @prime_pair : MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PrimePair?

    # Takes the components of RFC 8017 §3.2 as big-endian bytes (leading
    # zero bytes allowed): the modulus n, the public exponent e (or an
    # integer), the private exponent d, the primes p (*first_prime*) and q
    # (*second_prime*), d mod (p - 1) (*first_prime_exponent*), d mod
    # (q - 1) (*second_prime_exponent*) and q⁻¹ mod p (*coefficient*).
    #
    # Raises `KeySizeNotSupported` or `PublicExponentNotSupported` for a
    # modulus or exponent outside the ranges Beryl accepts, and
    # `MalformedPrivateKey` when the components do not belong together. The
    # checks on the secret components run in constant time and give one
    # verdict; then one private operation is run and checked with the public
    # exponent. *private_exponent* is checked to be below the modulus and is
    # not kept, since the Chinese remainder theorem does not need it.
    def initialize(*, modulus : Bytes, public_exponent : Bytes | Int, private_exponent : Bytes,
                   first_prime : Bytes, second_prime : Bytes, first_prime_exponent : Bytes,
                   second_prime_exponent : Bytes, coefficient : Bytes)
      @modulus = PublicKey.read_modulus(modulus, SMALLEST_MODULUS_BIT_COUNT, LARGEST_MODULUS_BIT_COUNT)
      @public_exponent = PublicKey.read_public_exponent(public_exponent)
      @public_exponent_correction = @modulus.public_exponent_correction(@public_exponent)
      if MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PublicModulus.usable_for?(@modulus.word_count)
        @modulus_in_digits = MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PublicModulus.new(@modulus.words,
          @modulus.r_squared, @modulus.negated_inverse, @public_exponent)
      end
      @modulus_bytesize = @modulus.bytesize
      @public_key = PublicKey.new(modulus, @public_exponent)

      @first_prime = OddModulus.from_bytes(first_prime)
      @second_prime = OddModulus.from_bytes(second_prime)
      smallest_prime_bit_count = (@modulus.bit_count + 1) // 2 - 64
      unless @first_prime.bit_count >= smallest_prime_bit_count && @second_prime.bit_count >= smallest_prime_bit_count &&
             @first_prime.word_count + @second_prime.word_count >= @modulus.word_count
        @first_prime.wipe
        @second_prime.wipe
        raise MalformedPrivateKey.new("the primes have #{@first_prime.bit_count} and #{@second_prime.bit_count} bits; " \
                                      "a #{@modulus.bit_count}-bit key needs two of about #{@modulus.bit_count // 2}")
      end

      is_well_formed = (@first_prime.words[0] & @second_prime.words[0] & 1_u64)
      @first_prime_exponent, fits_below = PrivateKey.read_component_below(first_prime_exponent, @first_prime)
      is_well_formed &= fits_below
      @second_prime_exponent, fits_below = PrivateKey.read_component_below(second_prime_exponent, @second_prime)
      is_well_formed &= fits_below
      coefficient_bytes, fits_below = PrivateKey.read_component_below(coefficient, @first_prime)
      is_well_formed &= fits_below
      @coefficient = Slice(UInt64).new(@first_prime.word_count)
      MontgomeryArithmetic.decode_big_endian(coefficient_bytes, @coefficient)
      SecretWiping.wipe(coefficient_bytes)
      private_exponent_bytes, fits_below = PrivateKey.read_component_below(private_exponent, @modulus)
      is_well_formed &= fits_below
      SecretWiping.wipe(private_exponent_bytes)
      is_well_formed &= primes_multiply_to_modulus_bit
      is_well_formed &= coefficient_inverts_second_prime_bit
      if MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PrimePair.usable_for?(@first_prime.word_count,
           @second_prime.word_count, @first_prime_exponent.size, @second_prime_exponent.size)
        @prime_pair = MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PrimePair.new(@first_prime.words,
          @first_prime.r_squared, @first_prime.negated_inverse, @second_prime.words, @second_prime.r_squared,
          @second_prime.negated_inverse)
      end

      unless Declassification.reveal(is_well_formed == 1_u64)
        wipe
        raise MalformedPrivateKey.new("the primes, exponents and coefficient do not belong together")
      end
      ensure_test_operation_inverts
    end

    # :nodoc:
    #
    # Reads *bytes* into a buffer as long as *modulus* and returns it with 1
    # when the value is below the modulus, or 0 otherwise. Constant time.
    def self.read_component_below(bytes : Bytes, modulus : OddModulus) : {Bytes, UInt64}
      words = Slice(UInt64).new(modulus.word_count)
      fits = MontgomeryArithmetic.decode_big_endian(bytes, words)
      is_below = fits & MontgomeryArithmetic.less_than_bit(words, modulus.words)
      component = Bytes.new(modulus.bytesize)
      MontgomeryArithmetic.encode_big_endian(words, component)
      SecretWiping.wipe(Bytes.new(words.to_unsafe.as(UInt8*), words.size * 8))
      {component, is_below}
    end

    # Returns 1 when p·q is the modulus, and 0 otherwise. Constant time.
    private def primes_multiply_to_modulus_bit : UInt64
      product_word_count = @first_prime.word_count + @second_prime.word_count
      product = Slice(UInt64).new(product_word_count)
      MontgomeryArithmetic.multiply_without_reduction(product, @first_prime.words, @second_prime.words)
      widened_modulus = Slice(UInt64).new(product_word_count)
      @modulus.words.copy_to(widened_modulus)
      is_equal = MontgomeryArithmetic.equal_bit(product, widened_modulus)
      wipe_words(product)
      is_equal
    end

    # Returns 1 when coefficient·q ≡ 1 (mod p), and 0 otherwise. Constant
    # time.
    private def coefficient_inverts_second_prime_bit : UInt64
      word_count = @first_prime.word_count
      second_prime_in_montgomery_form = Slice(UInt64).new(word_count)
      @first_prime.reduce_to_montgomery_form(second_prime_in_montgomery_form, @second_prime.words)
      product = Slice(UInt64).new(word_count)
      @first_prime.multiply(product, @coefficient, second_prime_in_montgomery_form)
      one = Slice(UInt64).new(word_count)
      one[0] = 1_u64
      is_inverse = MontgomeryArithmetic.equal_bit(product, one)
      wipe_words(second_prime_in_montgomery_form)
      wipe_words(product)
      is_inverse
    end

    # Runs the private operation on a fixed input; the check with the public
    # exponent fails unless the exponents belong to the primes.
    private def ensure_test_operation_inverts : Nil
      test_input = Bytes.new(@modulus_bytesize)
      test_input[@modulus_bytesize - 1] = KEY_TEST_INPUT.to_u8
      compute_private_operation(test_input, Bytes.new(@modulus_bytesize))
    rescue FaultInPrivateKeyOperation
      wipe
      raise MalformedPrivateKey.new("the private exponents do not invert the public exponent")
    end

    # The size of the modulus in bits.
    def modulus_bit_count : Int32
      @modulus.bit_count
    end

    # The size of a signature or a ciphertext under this key, in bytes.
    def modulus_bytesize : Int32
      @modulus_bytesize
    end

    # Returns the PKCS #1 v1.5 signature (RFC 8017 §8.2.1) of *message*
    # hashed with *hash_function*: `SHA224`, `SHA256`, `SHA384`, `SHA512` or
    # `SHA512_256`. The signature is the same every time.
    def sign_with_pkcs1(message : Bytes | String, *, hash_function : D.class) : Bytes forall D
      encoded = MessageEncoding.encode_pkcs1(MessageEncoding.digest_info_prefix(hash_function), D.digest(message), @modulus_bytesize)
      signature = Bytes.new(@modulus_bytesize)
      compute_private_operation(encoded, signature)
      signature
    end

    # Returns a PSS signature (RFC 8017 §8.1.1) of *message*, with
    # *hash_function* (a SHA-2 hash) for the message and for MGF1 and a
    # random salt of *salt_bytesize* bytes from `Random::Secure`. The usual
    # choice is a salt as long as the hash (TLS 1.3 requires it). Raises
    # `SaltTooLongForModulus` when the salt does not fit.
    def sign_with_pss(message : Bytes | String, *, hash_function : D.class, salt_bytesize : Int32) : Bytes forall D
      raise SaltTooLongForModulus.new("the salt size is negative: #{salt_bytesize}") if salt_bytesize < 0
      sign_with_pss_using_salt(message, Random::Secure.random_bytes(salt_bytesize), hash_function: hash_function)
    end

    # :nodoc:
    #
    # `sign_with_pss` with a given salt, for tests that must reproduce a
    # signature (NIST CAVP SigGenPSS).
    def sign_with_pss_using_salt(message : Bytes | String, salt : Bytes, *, hash_function : D.class) : Bytes forall D
      MessageEncoding.ensure_secure_hash_2(hash_function)
      encoded_bit_count = @modulus.bit_count - 1
      encoded = MessageEncoding.encode_pss(hash_function, D.digest(message), salt, encoded_bit_count)
      padded = Bytes.new(@modulus_bytesize)
      encoded.copy_to(padded[@modulus_bytesize - encoded.size, encoded.size])
      signature = Bytes.new(@modulus_bytesize)
      compute_private_operation(padded, signature)
      signature
    end

    # Returns the message inside *ciphertext*, encrypted with RSAES-OAEP
    # (RFC 8017 §7.1.2) with *hash_function* for the label and for MGF1
    # and the same *label*; or `nil` when the ciphertext is the wrong size,
    # is not below the modulus, or does not decode. Every one of those gives
    # the same `nil`, after the same work, so the response does not tell
    # them apart (the attack of Manger, 2001, needs it to).
    def decrypt_with_oaep(ciphertext : Bytes, *, hash_function : D.class, label : Bytes | String = Bytes.empty) : Bytes? forall D
      MessageEncoding.ensure_oaep_hash(hash_function)
      return nil unless ciphertext.size == @modulus_bytesize
      return nil if @modulus_bytesize < 2 * D::DIGEST_SIZE + 2

      encoded = Bytes.new(@modulus_bytesize)
      label_digest = D.digest(label.to_slice)
      verdict = DataIndependentTiming.run do
        MessageEncoding.decode_oaep(hash_function, encoded, label_digest, compute_private_operation(ciphertext, encoded))
      end
      revealed = Declassification.reveal(verdict)
      if revealed == 0_u32
        SecretWiping.wipe(encoded)
        return nil
      end

      message_bytesize = (revealed - 1).to_i32
      message = encoded[@modulus_bytesize - message_bytesize, message_bytesize].dup
      SecretWiping.wipe(encoded)
      message
    end

    # :nodoc:
    #
    # Writes input^d mod n into *output* (both `modulus_bytesize` bytes)
    # and returns 1, or, when *input* is not below the modulus, writes a
    # value of no use and returns 0. The work is the same either way.
    # Raises `FaultInPrivateKeyOperation`, writing nothing, when the result
    # raised to the public exponent does not give back the input. Runs under
    # `DataIndependentTiming`.
    def compute_private_operation(input : Bytes, output : Bytes) : UInt64
      DataIndependentTiming.run do
        word_count = @modulus.word_count
        input_words = Slice(UInt64).new(word_count)
        MontgomeryArithmetic.decode_big_endian(input, input_words)
        result_words = Slice(UInt64).new(word_count)
        is_in_range = PrivateKey.exponentiate_by_chinese_remainder(result_words, input_words, @first_prime, @second_prime,
          @first_prime_exponent, @second_prime_exponent, @coefficient, @modulus, @prime_pair)

        check_words = Slice(UInt64).new(word_count)
        if modulus_in_digits = @modulus_in_digits
          modulus_in_digits.exponentiate(check_words, result_words)
        else
          @modulus.exponentiate_by_public_exponent(check_words, result_words, @public_exponent, @public_exponent_correction)
        end
        is_correct = MontgomeryArithmetic.equal_bit(check_words, input_words) | (is_in_range ^ 1_u64)
        wipe_words(check_words)
        wipe_words(input_words)
        unless Declassification.reveal(is_correct == 1_u64)
          wipe_words(result_words)
          raise FaultInPrivateKeyOperation.new("the RSA private-key result did not check under the public exponent")
        end

        MontgomeryArithmetic.encode_big_endian(result_words, output)
        wipe_words(result_words)
        is_in_range
      end
    end

    # :nodoc:
    #
    # The private operation by the Chinese remainder theorem, after
    # BearSSL's `rsa_i31_priv.c`: the input is reduced into each prime's
    # Montgomery form chunk by chunk, raised to the prime's exponent, and
    # the two results are joined with Garner's formula,
    # m = m₂ + q·(qInv·(m₁ - m₂) mod p). Writes the result into *result*
    # (as many words as the modulus) and returns 1 when *input* is below
    # the modulus, and 0 otherwise. Constant time; reveals nothing.
    def self.exponentiate_by_chinese_remainder(result : Slice(UInt64), input : Slice(UInt64), first_prime : OddModulus,
                                               second_prime : OddModulus, first_prime_exponent : Bytes,
                                               second_prime_exponent : Bytes, coefficient : Slice(UInt64),
                                               modulus : OddModulus,
                                               prime_pair : MontgomeryMultiplicationWithIntegerFusedMultiplyAdd::PrimePair? = nil) : UInt64
      is_in_range = MontgomeryArithmetic.less_than_bit(input, modulus.words)
      first_word_count = first_prime.word_count
      second_word_count = second_prime.word_count

      base = Slice(UInt64).new(first_word_count)
      first_power = Slice(UInt64).new(first_word_count)
      first_prime.reduce_to_montgomery_form(base, input)
      second_base = Slice(UInt64).new(second_word_count)
      second_power = Slice(UInt64).new(second_word_count)
      second_prime.reduce_to_montgomery_form(second_base, input)
      if prime_pair
        # Both exponentiations at once; the second result leaves Montgomery
        # form there.
        prime_pair.exponentiate(first_power, second_power, base, second_base, first_prime_exponent, second_prime_exponent)
      else
        first_prime.exponentiate(first_power, base, first_prime_exponent)
        second_prime.exponentiate(second_power, second_base, second_prime_exponent)
        second_prime.leave_montgomery_form(second_power)
      end

      # m₁ - m₂ mod p, in p's Montgomery form, times qInv: the Montgomery
      # product drops the factor R, leaving h = qInv·(m₁ - m₂) mod p.
      first_prime.reduce_to_montgomery_form(base, second_power)
      first_prime.subtract(first_power, first_power, base)
      first_prime.multiply(base, coefficient, first_power)

      product = Slice(UInt64).new(first_word_count + second_word_count)
      MontgomeryArithmetic.multiply_without_reduction(product, second_prime.words, base)
      carry = 0_u64
      product.size.times do |index|
        addend = index < second_word_count ? second_power[index] : 0_u64
        sum = product[index].to_u128 &+ addend.to_u128 &+ carry.to_u128
        product[index] = sum.to_u64!
        carry = (sum >> 64).to_u64!
      end
      product[0, result.size].copy_to(result)

      {base, first_power, second_base, second_power, product}.each do |words|
        SecretWiping.wipe(Bytes.new(words.to_unsafe.as(UInt8*), words.size * 8))
      end
      is_in_range
    end

    # Overwrites the secret parts of the key. The key cannot be used after.
    def wipe : Nil
      if prime_pair = @prime_pair
        prime_pair.wipe
      end
      @first_prime.wipe
      @second_prime.wipe
      SecretWiping.wipe(@first_prime_exponent)
      SecretWiping.wipe(@second_prime_exponent)
      wipe_words(@coefficient)
    end

    def finalize
      wipe
    end

    private def wipe_words(words : Slice(UInt64)) : Nil
      SecretWiping.wipe(Bytes.new(words.to_unsafe.as(UInt8*), words.size * 8))
    end
  end
end
