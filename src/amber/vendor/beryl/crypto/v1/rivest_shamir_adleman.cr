require "random/secure"
require "../data_independent_timing"
require "./montgomery_arithmetic"
require "./rivest_shamir_adleman/odd_modulus"
require "./rivest_shamir_adleman/message_encoding"
require "./rivest_shamir_adleman/public_key"
require "./rivest_shamir_adleman/private_key"

module Amber::Beryl::Crypto::V1
  # RSA (RFC 8017), for the signatures in certificates and TLS handshakes
  # and for the RSA-OAEP that MySQL's `caching_sha2_password` uses.
  #
  # | Scheme | Sign or encrypt | Verify or decrypt |
  # |---|---|---|
  # | PKCS #1 v1.5 signatures (§8.2) | `PrivateKey#sign_with_pkcs1` | `PublicKey#verify_pkcs1_signature` |
  # | PSS signatures (§8.1) | `PrivateKey#sign_with_pss` | `PublicKey#verify_pss_signature` |
  # | OAEP encryption (§7.1) | `PublicKey#encrypt_with_oaep` | `PrivateKey#decrypt_with_oaep` |
  #
  # Each call names its hash with `hash_function:`, a hash class such as
  # `Amber::Beryl::Crypto::V1::SHA256`; PSS and OAEP use the same hash for MGF1.
  # PKCS #1 v1.5 signs with SHA-224, SHA-256, SHA-384, SHA-512 or
  # SHA-512/256 and also verifies SHA-1; PSS takes those SHA-2 hashes;
  # OAEP takes them and SHA-1.
  #
  # ```
  # public_key = Amber::Beryl::Crypto::V1::RSA::PublicKey.new(modulus, 65_537)
  # ciphertext = public_key.encrypt_with_oaep("password", hash_function: Amber::Beryl::Crypto::Compatibility::SHA1)
  # private_key.decrypt_with_oaep(ciphertext, hash_function: Amber::Beryl::Crypto::Compatibility::SHA1) # => the bytes of "password"
  # ```
  #
  # Public keys of 2,048 to 8,192 bits and private keys of 2,048 to 4,096
  # bits are accepted; public exponents are odd, from 3 to 2^32 - 1.
  module RivestShamirAdleman
  end

  alias RSA = RivestShamirAdleman
end
