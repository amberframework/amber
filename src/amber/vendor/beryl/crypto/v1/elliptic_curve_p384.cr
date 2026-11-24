require "../error"
require "./secure_hash_with_384_bit_digest"
require "./prime_order_curve_arithmetic"
require "./prime_order_curve_keys"

module Amber::Beryl::Crypto::V1
  # NIST P-384 (secp384r1, FIPS 186-5, SP 800-186): ECDSA verification,
  # with SHA-384 by default and any SHA-2 digest through `verify_digest`.
  # Let's Encrypt's ECDSA intermediates and ISRG Root X2 are P-384 keys, so
  # a TLS client needs this to check certificate chains. Signing and ECDH
  # on P-384 are not offered.
  #
  # ```
  # key = Amber::Beryl::Crypto::V1::P384::PublicKey.new(encoded_point)
  # key.verify(message, der_signature) # => true or false
  # ```
  module EllipticCurveP384
    # :nodoc:
    module Arithmetic
      ::Amber::Beryl::Crypto::V1.define_prime_order_curve_arithmetic(
        Amber::Beryl::Crypto::FieldArithmetic::P384FieldWithAssembly,
        Amber::Beryl::Crypto::FieldArithmetic::P384ScalarFieldWithAssembly,
        48,
        "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffeffffffff0000000000000000ffffffff",
        "ffffffffffffffffffffffffffffffffffffffffffffffffc7634d81f4372ddf581a0db248b0a77aecec196accc52973",
        "b3312fa7e23ee7e4988e056be3f82d19181d9c6efe8141120314088f5013875ac656398d8a2ed19d2a85c8edd3ec2aef",
        "aa87ca22be8b05378eb1c71ef320ad746e1d3b628ba79b9859f741e082542a385502f25dbf55296c3a545e3872760ab7",
        "3617de4a96262c6f5d9e98bf9292dc29f8f41dbd289a147ce9da3113b5f0b8c00a60b1ce1d7e819d7a431d7c90ea0e5f",
      )
    end

    ::Amber::Beryl::Crypto::V1.define_prime_order_curve_keys(Arithmetic, SHA384, "P-384", false)
  end

  alias P384 = EllipticCurveP384
end
