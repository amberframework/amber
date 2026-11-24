require "random/secure"
require "./crypto/error"
require "./crypto/v1"
require "./crypto/compatibility"

# Cryptography written in Crystal.
#
# The calls on this module always use the algorithm Beryl recommends today:
#
# ```
# Amber::Beryl::Crypto.digest("contents of a file")                             # SHA-256
# tag = Amber::Beryl::Crypto.authenticate("message", key: secret_key)           # HMAC-SHA256
# Amber::Beryl::Crypto.verify_authentication("message", tag, key: secret_key)   # => true
# Amber::Beryl::Crypto.derive_key(shared_secret, info: "cookies", bytesize: 32) # HKDF-SHA256
# sealed = Amber::Beryl::Crypto.encrypt("a private note", key: secret_key)      # XChaCha20-Poly1305
# Amber::Beryl::Crypto.decrypt(sealed, key: secret_key)                         # => the note, or nil
# signing_key = Amber::Beryl::Crypto.generate_signing_key                       # Ed25519
# signature = Amber::Beryl::Crypto.sign("a message", signing_key: signing_key)
# Amber::Beryl::Crypto.verify_signature("a message", signature, verification_key: signing_key.verification_key) # => true
# mine = Amber::Beryl::Crypto.generate_key_agreement_key                                                        # X25519
# Amber::Beryl::Crypto.agree_on_shared_secret(mine, peer_public_key)                                            # => 32 bytes, or nil
# ```
#
# `Amber::Beryl::Crypto::V1` names each algorithm exactly, for code that must keep
# producing the same bytes. `Amber::Beryl::Crypto::Compatibility` holds MD5, SHA-1,
# PBKDF2 and AES-CBC for formats that require them.
module Amber::Beryl::Crypto
  # Returns the SHA-256 digest of *data* (32 bytes).
  def self.digest(data : Bytes | String) : Bytes
    V1::SHA256.digest(data)
  end

  # Returns the HMAC-SHA256 authentication tag of *message* under *key*
  # (32 bytes).
  def self.authenticate(message : Bytes | String, *, key : Bytes | String) : Bytes
    V1::HMAC(V1::SHA256).authenticate(message, key: key)
  end

  # Returns whether *authentication_tag* is the HMAC-SHA256 tag of *message*
  # under *key*. The comparison runs in constant time.
  def self.verify_authentication(message : Bytes | String, authentication_tag : Bytes, *, key : Bytes | String) : Bool
    V1::HMAC(V1::SHA256).verify(message, authentication_tag, key: key)
  end

  # Returns *bytesize* bytes of key derived from *input_key_material* with
  # HKDF-SHA256. *info* names the purpose, so that different purposes get
  # unrelated keys; *salt* is optional and need not be secret.
  def self.derive_key(
    input_key_material : Bytes | String,
    *,
    salt : Bytes | String = Bytes.empty,
    info : Bytes | String = Bytes.empty,
    bytesize : Int32 = 32,
  ) : Bytes
    V1::HKDF(V1::SHA256).derive_key(input_key_material, salt: salt, info: info, bytesize: bytesize)
  end

  # The size of the random nonce `encrypt` places in front of each message.
  ENCRYPTED_MESSAGE_NONCE_BYTESIZE = V1::XChaCha20Poly1305::NONCE_BYTESIZE

  # Returns *message* encrypted and authenticated under *key* (32 bytes)
  # with XChaCha20-Poly1305: a fresh random nonce (24 bytes), then the
  # ciphertext, then the tag (16 bytes). *associated_data* is authenticated
  # and left out of the result; `decrypt` must be given the same bytes.
  def self.encrypt(message : Bytes | String, *, key : Bytes, associated_data : Bytes | String = Bytes.empty) : Bytes
    message_bytes = message.to_slice
    cipher = V1::XChaCha20Poly1305.new(key)
    encrypted_message = Bytes.new(ENCRYPTED_MESSAGE_NONCE_BYTESIZE + message_bytes.size + cipher.tag_bytesize)
    nonce = encrypted_message[0, ENCRYPTED_MESSAGE_NONCE_BYTESIZE]
    Random::Secure.random_bytes(nonce)
    cipher.encrypt(
      message_bytes,
      into: encrypted_message[ENCRYPTED_MESSAGE_NONCE_BYTESIZE, message_bytes.size + cipher.tag_bytesize],
      nonce: nonce,
      associated_data: associated_data,
    )
    encrypted_message
  end

  # Returns the message inside *encrypted_message* (the result of
  # `encrypt`), or `nil` when it was altered, was encrypted under another
  # key, or goes with other associated data.
  def self.decrypt(encrypted_message : Bytes, *, key : Bytes, associated_data : Bytes | String = Bytes.empty) : Bytes?
    cipher = V1::XChaCha20Poly1305.new(key)
    return nil if encrypted_message.size < ENCRYPTED_MESSAGE_NONCE_BYTESIZE + cipher.tag_bytesize

    cipher.decrypt(
      encrypted_message[ENCRYPTED_MESSAGE_NONCE_BYTESIZE, encrypted_message.size - ENCRYPTED_MESSAGE_NONCE_BYTESIZE],
      nonce: encrypted_message[0, ENCRYPTED_MESSAGE_NONCE_BYTESIZE],
      associated_data: associated_data,
    )
  end

  # Returns a new Ed25519 signing key (RFC 8032). Its `verification_key`
  # is the public half to hand out.
  def self.generate_signing_key : V1::Ed25519::SigningKey
    V1::Ed25519::SigningKey.generate
  end

  # Returns the Ed25519 signature of *message* (64 bytes).
  def self.sign(message : Bytes | String, *, signing_key : V1::Ed25519::SigningKey) : Bytes
    signing_key.sign(message)
  end

  # Returns whether *signature* is the Ed25519 signature of *message* under
  # *verification_key*.
  def self.verify_signature(message : Bytes | String, signature : Bytes, *, verification_key : V1::Ed25519::VerificationKey) : Bool
    verification_key.verify(message, signature)
  end

  # Returns a new X25519 key agreement key (RFC 7748). Its `public_key` is
  # the half to send to the peer.
  def self.generate_key_agreement_key : V1::X25519::PrivateKey
    V1::X25519::PrivateKey.generate
  end

  # Returns the 32-byte X25519 shared secret of *own_key* and
  # *peer_public_key*, or `nil` when the peer sent a point of small order.
  # Derive keys from it with `derive_key`; never use it as a key directly.
  def self.agree_on_shared_secret(own_key : V1::X25519::PrivateKey, peer_public_key : V1::X25519::PublicKey) : Bytes?
    own_key.shared_secret(peer_public_key)
  end
end
