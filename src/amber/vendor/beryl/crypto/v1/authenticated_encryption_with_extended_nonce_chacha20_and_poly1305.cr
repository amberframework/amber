require "./authenticated_encryption_with_chacha20_and_poly1305"

module Amber::Beryl::Crypto::V1
  # XChaCha20-Poly1305 (draft-irtf-cfrg-xchacha-03): ChaCha20-Poly1305 with
  # a 24-byte nonce, long enough to pick at random for every message. This is
  # the cipher behind `Amber::Beryl::Crypto.encrypt`.
  #
  # ```
  # cipher = Amber::Beryl::Crypto::V1::XChaCha20Poly1305.new(key)
  # nonce = Random::Secure.random_bytes(24)
  # sealed = cipher.encrypt(body, nonce: nonce)
  # cipher.decrypt(sealed, nonce: nonce) # => body, or nil
  # ```
  #
  # The first 16 nonce bytes and the key give a one-message key (HChaCha20);
  # the last 8 nonce bytes are the nonce of an ordinary ChaCha20-Poly1305
  # under that key.
  class AuthenticatedEncryptionWithExtendedNonceChaCha20AndPoly1305 < AuthenticatedEncryption
    KEY_BYTESIZE   = 32
    NONCE_BYTESIZE = 24

    @key : Bytes

    # Creates the cipher under *key* (32 bytes), which is copied.
    def initialize(key : Bytes)
      raise KeySizeMismatch.new("an XChaCha20-Poly1305 key is #{KEY_BYTESIZE} bytes, not #{key.size}") unless key.size == KEY_BYTESIZE

      @key = key.dup
    end

    def nonce_bytesize : Int32
      NONCE_BYTESIZE
    end

    protected def ensure_nonce_is_accepted(nonce : Bytes) : Nil
      return if nonce.size == NONCE_BYTESIZE

      raise NonceSizeMismatch.new("an XChaCha20-Poly1305 nonce is #{NONCE_BYTESIZE} bytes, not #{nonce.size}")
    end

    protected def apply_keystream(nonce : Bytes, input : Bytes, output : Bytes) : Nil
      with_message_key(nonce) do |message_key, message_nonce|
        ChaCha20Poly1305Construction.apply_keystream(message_key, message_nonce, input, output)
      end
    end

    protected def compute_tag(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      with_message_key(nonce) do |message_key, message_nonce|
        ChaCha20Poly1305Construction.compute_tag(message_key, message_nonce, associated_data, ciphertext, full_tag)
      end
    end

    # Yields the key and the 12-byte nonce this message is encrypted under,
    # then wipes the key.
    private def with_message_key(nonce : Bytes, & : Bytes, Bytes -> Nil) : Nil
      message_key_storage = uninitialized UInt8[32]
      message_key = message_key_storage.to_slice
      ChaCha20StreamCipher.derive_subkey(@key, nonce[0, ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE], message_key)

      message_nonce_storage = StaticArray(UInt8, 12).new(0_u8)
      message_nonce = message_nonce_storage.to_slice
      nonce[ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE, 8].copy_to(message_nonce[4, 8])

      yield message_key, message_nonce
      SecretWiping.wipe(message_key)
    end
  end

  # The common name of `AuthenticatedEncryptionWithExtendedNonceChaCha20AndPoly1305`.
  alias XChaCha20Poly1305 = AuthenticatedEncryptionWithExtendedNonceChaCha20AndPoly1305
end
