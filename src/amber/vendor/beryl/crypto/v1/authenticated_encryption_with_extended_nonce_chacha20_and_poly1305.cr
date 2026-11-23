require "crypto/subtle"
require "../declassification"
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

    protected def seal(nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      {% if flag?(:aarch64) %}
        if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS && plaintext.size <= ChaCha20WithVectorInstructions::LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE
          ChaCha20WithVectorInstructions.with_short_extended_keystream(@key, nonce, plaintext) do |one_time_key, encrypted|
            encrypted.copy_to(ciphertext)
            ChaCha20WithVectorInstructions.authenticate(one_time_key, associated_data, ciphertext, full_tag)
          end
          return
        end
      {% end %}
      with_message_key(nonce) do |message_key, message_nonce|
        ChaCha20Poly1305Construction.seal(message_key, message_nonce, associated_data, plaintext, ciphertext, full_tag)
      end
    end

    protected def open(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      is_authentic = false
      {% if flag?(:aarch64) %}
        if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS && ciphertext.size <= ChaCha20WithVectorInstructions::LONGEST_SHORT_EXTENDED_MESSAGE_BYTESIZE
          ChaCha20WithVectorInstructions.with_short_extended_keystream(@key, nonce, ciphertext) do |one_time_key, decrypted|
            full_tag_storage = uninitialized UInt8[16]
            full_tag = full_tag_storage.to_slice
            ChaCha20WithVectorInstructions.authenticate(one_time_key, associated_data, ciphertext, full_tag)
            tags_match = ::Crypto::Subtle.constant_time_compare(full_tag[0, tag.size], tag)
            SecretWiping.wipe(full_tag)
            is_authentic = Declassification.reveal(tags_match)
            decrypted.copy_to(plaintext) if is_authentic
          end
          return is_authentic
        end
      {% end %}
      with_message_key(nonce) do |message_key, message_nonce|
        is_authentic = ChaCha20Poly1305Construction.open(message_key, message_nonce, associated_data, ciphertext, tag, plaintext)
      end
      is_authentic
    end

    # Yields the key and the 12-byte nonce this message is encrypted under,
    # then wipes the key.
    private def with_message_key(nonce : Bytes, & : Bytes, Bytes -> Nil) : Nil
      message_key_storage = uninitialized UInt8[32]
      message_key = message_key_storage.to_slice
      {% if flag?(:aarch64) %}
        if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS
          ChaCha20WithVectorInstructions.derive_subkey(@key, nonce[0, ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE], message_key)
        else
          ChaCha20StreamCipher.derive_subkey(@key, nonce[0, ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE], message_key)
        end
      {% else %}
        ChaCha20StreamCipher.derive_subkey(@key, nonce[0, ChaCha20StreamCipher::SUBKEY_NONCE_BYTESIZE], message_key)
      {% end %}

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
