require "./compatibility/message_digest_5"
require "./compatibility/secure_hash_algorithm_1"
require "./compatibility/password_based_key_derivation_function_2"
require "./compatibility/advanced_encryption_standard_in_cipher_block_chaining_mode"

# Algorithms kept only to read and speak formats that already exist. None of
# them is the right choice for a new design, and the convenience calls on
# `Amber::Beryl::Crypto` never use them.
#
# | Alias | Class | Standard | Still needed by |
# |---|---|---|---|
# | `MD5` | `MessageDigest5` | RFC 1321 | PostgreSQL md5 authentication, bit-exact lock ids and cache keys |
# | `SHA1` | `SecureHashAlgorithm1` | FIPS 180-4 | WebSocket handshakes, UUID v5, MySQL authentication |
# | `PBKDF2(D)` | `PasswordBasedKeyDerivationFunction2(D)` | RFC 8018 | PostgreSQL SCRAM |
# | `AESCBC` | `AdvancedEncryptionStandardInCipherBlockChainingMode` | FIPS 197, SP 800-38A | Amber version 1 cookies, Grant version 1 encrypted attributes |
#
# HMAC over these hashes is `V1::HMAC(Compatibility::SHA1)` and
# `V1::HMAC(Compatibility::MD5)`: the word `Compatibility` always appears
# where an old algorithm is chosen.
module Amber::Beryl::Crypto::Compatibility
end
