require "./authenticated_encryption"
require "./chacha20_stream_cipher"
require "./chacha20_with_vector_instructions"
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

    # Zeroes this cipher's copy of the key.
    protected def wipe_key_material : Nil
      SecretWiping.wipe(@key)
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

    protected def seal(nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      ChaCha20Poly1305Construction.seal(@key, nonce, associated_data, plaintext, ciphertext, full_tag)
    end

    protected def open(nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      ChaCha20Poly1305Construction.open(@key, nonce, associated_data, ciphertext, tag, plaintext)
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
      if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS
        ChaCha20WithVectorInstructions.xor_keystream(key, nonce, 1_u32, input, output)
      else
        ChaCha20StreamCipher.xor_keystream(key, nonce, 1_u32, input, output)
      end
    end

    def self.compute_tag(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS
        ChaCha20WithVectorInstructions.write_tag(key, nonce, associated_data, ciphertext, full_tag)
        return
      end

      one_time_key_storage = StaticArray(UInt8, 32).new(0_u8)
      one_time_key = one_time_key_storage.to_slice
      ChaCha20StreamCipher.xor_keystream(key, nonce, 0_u32, one_time_key, one_time_key)
      Poly1305OneTimeAuthenticator.authenticate_encrypted_message(one_time_key, associated_data, ciphertext, full_tag)
      SecretWiping.wipe(one_time_key)
    end

    # Encrypts and authenticates; on the vector instructions, block 0 and
    # the start of the message come from one pass.
    def self.seal(key : Bytes, nonce : Bytes, associated_data : Bytes, plaintext : Bytes, ciphertext : Bytes, full_tag : Bytes) : Nil
      if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS
        ChaCha20WithVectorInstructions.seal(key, nonce, associated_data, plaintext, ciphertext, full_tag)
      else
        apply_keystream(key, nonce, plaintext, ciphertext)
        compute_tag(key, nonce, associated_data, ciphertext, full_tag)
      end
    end

    # Checks *tag* against the first `tag.size` bytes of the right tag, then
    # decrypts into *plaintext*; returns false without writing *plaintext*
    # when the tag is wrong (`AuthenticatedEncryption#decrypt` then zeroes it).
    def self.open(key : Bytes, nonce : Bytes, associated_data : Bytes, ciphertext : Bytes, tag : Bytes, plaintext : Bytes) : Bool
      if ProcessorFeatures::HAS_VECTOR_INSTRUCTIONS
        return ChaCha20WithVectorInstructions.open(key, nonce, associated_data, ciphertext, tag, plaintext)
      end

      full_tag_storage = uninitialized UInt8[16]
      compute_tag(key, nonce, associated_data, ciphertext, full_tag_storage.to_slice)
      tags_match = ::Crypto::Subtle.constant_time_compare(full_tag_storage.to_slice[0, tag.size], tag)
      SecretWiping.wipe(full_tag_storage.to_slice)
      return false unless Declassification.reveal(tags_match)

      apply_keystream(key, nonce, ciphertext, plaintext)
      true
    end
  end
end
