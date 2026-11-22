require "./authenticated_encryption"
require "./chacha20_stream_cipher"
require "./poly1305_one_time_authenticator"

module Amber::Beryl::Crypto::V1
  # ChaCha20-Poly1305 (RFC 8439 §2.8): authenticated encryption under a
  # 32-byte key and a 12-byte nonce. It is the cipher of COSE algorithm 24
  # and of TLS 1.3's `TLS_CHACHA20_POLY1305_SHA256`.
  #
  # ```
  # cipher = Amber::Beryl::Crypto::V1::ChaCha20Poly1305.new(key)
  # sealed = cipher.encrypt(body, nonce: nonce, associated_data: header)
  # cipher.decrypt(sealed, nonce: nonce, associated_data: header) # => body, or nil
  # ```
  #
  # A 12-byte nonce is too short to pick at random for many messages under
  # one key; count it, or use `XChaCha20Poly1305`, whose 24-byte nonce may be
  # random.
  class AuthenticatedEncryptionWithChaCha20AndPoly1305 < AuthenticatedEncryption
    KEY_BYTESIZE   = 32
    NONCE_BYTESIZE = 12

    @key : Bytes

    # Creates the cipher under *key* (32 bytes), which is copied.
    def initialize(key : Bytes)
      raise KeySizeMismatch.new("a ChaCha20-Poly1305 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE

      @key = key.dup
    end

    def nonce_bytesize : Int32
      NONCE_BYTESIZE
    end

    protected def ensure_nonce_is_accepted(nonce : Bytes) : Nil
      return if nonce.size == NONCE_BYTESIZE

      raise NonceSizeMismatch.new("a ChaCha20-Poly1305 nonce is #{NONCE_BYTESIZE} bytes, not #{nonce.size}")
    end

    protected def apply_keystream(nonce : Bytes, input : Bytes, output : Bytes) : Nil
      ChaCha20Poly1305Construction.apply_keystream(@key, nonce, input, output)
    end

    protected def compute_tag(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      ChaCha20Poly1305Construction.compute_tag(@key, nonce, associated_data, ciphertext, full_tag)
    end
  end

  # The common name of `AuthenticatedEncryptionWithChaCha20AndPoly1305`.
  alias ChaCha20Poly1305 = AuthenticatedEncryptionWithChaCha20AndPoly1305

  # :nodoc:
  #
  # How RFC 8439 §2.8 puts ChaCha20 and Poly1305 together, for a key and a
  # 12-byte nonce. Every buffer is treated as secret.
  module ChaCha20Poly1305Construction
    # The message is encrypted from block 1; block 0 gives the Poly1305 key.
    def self.apply_keystream(key : Bytes, nonce : Bytes, input : Bytes, output : Bytes) : Nil
      ChaCha20StreamCipher.xor_keystream(key, nonce, 1_u32, input, output)
    end

    def self.compute_tag(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      one_time_key_storage = StaticArray(UInt8, 32).new(0_u8)
      one_time_key = one_time_key_storage.to_slice
      ChaCha20StreamCipher.xor_keystream(key, nonce, 0_u32, one_time_key, one_time_key)
      Poly1305OneTimeAuthenticator.authenticate_encrypted_message(one_time_key, associated_data, ciphertext, full_tag)
      SecretWiping.wipe(one_time_key)
    end
  end
end
