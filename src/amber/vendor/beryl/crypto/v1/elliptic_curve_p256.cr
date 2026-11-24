require "random/secure"
require "../error"
require "../secret_wiping"
require "../declassification"
require "./secure_hash_with_256_bit_digest"
require "./prime_order_curve_arithmetic"
require "./deterministic_signature_nonce"
require "./elliptic_curve_signature_encoding"
require "./prime_order_curve_keys"

module Amber::Beryl::Crypto::V1
  # NIST P-256 (secp256r1, FIPS 186-5, SP 800-186): ECDSA signatures with
  # SHA-256 and RFC 6979 deterministic nonces, and ECDH.
  #
  # ```
  # key = Amber::Beryl::Crypto::V1::P256::PrivateKey.generate
  # signature = key.sign("a message")                  # DER, as TLS writes it
  # key.public_key.verify("a message", signature)      # => true
  # key.shared_secret(P256::PublicKey.new(peer_point)) # 32 bytes, the x coordinate
  # ```
  #
  # Key generation, signing and ECDH multiply by a secret scalar in
  # constant time, on field arithmetic in assembly that equals fiat-crypto's
  # output for every input (`FieldArithmetic::P256FieldWithAssembly`).
  # Verification is variable time; its inputs are public.
  module EllipticCurveP256
    # :nodoc:
    module Arithmetic
      ::Amber::Beryl::Crypto::V1.define_prime_order_curve_arithmetic(
        Amber::Beryl::Crypto::FieldArithmetic::P256FieldWithAssembly,
        Amber::Beryl::Crypto::FieldArithmetic::P256ScalarFieldWithAssembly,
        32,
        "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff",
        "ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551",
        "5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b",
        "6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296",
        "4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5",
      )
    end

    ::Amber::Beryl::Crypto::V1.define_prime_order_curve_keys(Arithmetic, SHA256, "P-256", true)
  end

  alias P256 = EllipticCurveP256
end
