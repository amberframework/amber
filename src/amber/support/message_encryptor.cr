require "json"
require "crypto/subtle"
require "random/secure"

require "../vendor/beryl/crypto"
require "./message_authentication"
require "./message_verifier"

module Amber::Support
  # Encrypts a message so that it can travel through a cookie or sit in a
  # file and come back private and unchanged.
  #
  # ## Format version 2 (written by every call)
  #
  #     "AMB2" (4 bytes) | nonce (24 bytes) | ciphertext | tag (16 bytes)
  #
  # XChaCha20-Poly1305 under a key derived from the secret with HKDF-SHA256
  # (info `"amber message encryptor v2"`). The four header bytes are
  # authenticated with the message, and the nonce is random for each one.
  #
  # ## Format version 1 (still read)
  #
  #     ciphertext | initialization vector (16 bytes) | HMAC tag (32 bytes)
  #
  # AES-256-CBC with HMAC-SHA256, the format of Amber up to 2.0.0-beta.13.
  # `verify_and_decrypt` reads it under the current secret and under each of
  # *previous_secrets*, so cookies and encrypted files written before the
  # upgrade keep working and are rewritten in version 2 the next time they
  # are saved.
  #
  # ```
  # encryptor = Amber::Support::MessageEncryptor.new(secret, previous_secrets: [old_secret])
  # sealed = encryptor.encrypt_and_sign("user_id=42")
  # String.new(encryptor.verify_and_decrypt(sealed)) # => "user_id=42"
  # ```
  class MessageEncryptor
    Log = ::Log.for(self)

    # The first bytes of a version 2 message.
    VERSION_2_HEADER = "AMB2".to_slice

    VERSION_2_KEY_PURPOSE = "amber message encryptor v2"

    # The only cipher of format version 1.
    VERSION_1_CIPHER_ALGORITHM = "aes-256-cbc"

    private NONCE_BYTESIZE           = Amber::Beryl::Crypto::V1::XChaCha20Poly1305::NONCE_BYTESIZE
    private TAG_BYTESIZE             = Amber::Beryl::Crypto::V1::AuthenticatedEncryption::FULL_TAG_BYTESIZE
    private VERSION_1_KEY_BYTESIZE   = 32
    private VERSION_1_BLOCK_BYTESIZE = 16

    getter verifier : MessageVerifier

    @encryption_key : String
    @signing_key : String
    @previous_secrets : Array(String)
    @digest : Symbol
    @signature_size : Int32

    # *cipher_algorithm* names the cipher of version 1 messages and must be
    # `"aes-256-cbc"`; *digest* is the HMAC of version 1 messages (`:sha256`,
    # `:sha384`, `:sha512` or `:sha1`). Neither changes what is written.
    def initialize(@secret : String, cipher_algorithm : String = VERSION_1_CIPHER_ALGORITHM, digest : Symbol | String = :sha256,
                   @previous_secrets = [] of String)
      unless cipher_algorithm.downcase == VERSION_1_CIPHER_ALGORITHM
        raise ArgumentError.new(
          "Amber reads version 1 messages encrypted with #{VERSION_1_CIPHER_ALGORITHM}; #{cipher_algorithm.inspect} is not supported"
        )
      end
      @digest = MessageAuthentication.supported_digest_name(digest)
      @encryption_key = derive_key(@secret, "amber.encryption")
      @signing_key = derive_key(@secret, "amber.signing")
      @verifier = MessageVerifier.new(@signing_key, digest: @digest)
      @signature_size = MessageAuthentication.tag_bytesize(@digest)
    end

    # Returns the message inside *value*, which may be in format version 2
    # or 1, written under the current secret or a previous one. Raises when
    # no secret opens it.
    def verify_and_decrypt(value : Bytes) : Bytes
      result = decrypt_version_2(value)
      return result if result

      # Try current derived keys first
      result = try_verify_and_decrypt(value, @encryption_key, @signing_key)
      return result if result

      # Try with previous secrets for key rotation support
      @previous_secrets.each do |old_secret|
        old_enc_key = derive_key(old_secret, "amber.encryption")
        old_sign_key = derive_key(old_secret, "amber.signing")
        result = try_verify_and_decrypt(value, old_enc_key, old_sign_key)
        if result
          Log.info { "Message decrypted with rotated secret key" }
          return result
        end

        # Also try the legacy single-key format for backward compatibility
        result = try_verify_and_decrypt(value, old_secret, old_secret)
        if result
          Log.info { "Message decrypted with legacy single-key format" }
          return result
        end
      end

      # Also try legacy single-key format with current secret for backward compatibility
      result = try_verify_and_decrypt(value, @secret, @secret)
      if result
        Log.info { "Message decrypted with legacy single-key format (current secret)" }
        return result
      end

      raise "Decryption failed with all available secrets"
    end

    # Returns *value* encrypted and authenticated, in format version 2.
    def encrypt_and_sign(value)
      encrypt(value, sign: true)
    end

    # Returns *value* encrypted and authenticated, in format version 2.
    # Every version 2 message is authenticated, so *sign* no longer changes
    # the result; it stays for callers written against version 1.
    def encrypt(value, sign = false)
      message = value.to_slice
      cipher = Amber::Beryl::Crypto::V1::XChaCha20Poly1305.new(version_2_key(@secret))
      encrypted = Bytes.new(VERSION_2_HEADER.size + NONCE_BYTESIZE + message.size + TAG_BYTESIZE)
      VERSION_2_HEADER.copy_to(encrypted)
      nonce = encrypted[VERSION_2_HEADER.size, NONCE_BYTESIZE]
      Random::Secure.random_bytes(nonce)
      cipher.encrypt(
        message,
        into: encrypted[VERSION_2_HEADER.size + NONCE_BYTESIZE, message.size + TAG_BYTESIZE],
        nonce: nonce,
        associated_data: VERSION_2_HEADER,
      )
      encrypted
    end

    # Returns the message inside *value*: a version 2 message under the
    # current secret or a previous one, or a version 1 message that was
    # written without a signature (`encrypt(value)` before version 2).
    def decrypt(value : Bytes)
      decrypt_version_2(value) || decrypt_with_key(value, @encryption_key)
    end

    # Returns the message inside a version 2 *value*, or nil when *value* is
    # not version 2 or no secret opens it.
    private def decrypt_version_2(value : Bytes) : Bytes?
      return nil if value.size < VERSION_2_HEADER.size + NONCE_BYTESIZE + TAG_BYTESIZE
      return nil unless value[0, VERSION_2_HEADER.size] == VERSION_2_HEADER

      nonce = value[VERSION_2_HEADER.size, NONCE_BYTESIZE]
      sealed = value[VERSION_2_HEADER.size + NONCE_BYTESIZE, value.size - VERSION_2_HEADER.size - NONCE_BYTESIZE]
      result = open_version_2(@secret, nonce, sealed)
      return result if result

      @previous_secrets.each do |old_secret|
        result = open_version_2(old_secret, nonce, sealed)
        if result
          Log.info { "Message decrypted with rotated secret key" }
          return result
        end
      end
      nil
    end

    private def open_version_2(secret : String, nonce : Bytes, sealed : Bytes) : Bytes?
      cipher = Amber::Beryl::Crypto::V1::XChaCha20Poly1305.new(version_2_key(secret))
      cipher.decrypt(sealed, nonce: nonce, associated_data: VERSION_2_HEADER)
    end

    private def version_2_key(secret : String) : Bytes
      Amber::Beryl::Crypto::V1::HKDF(Amber::Beryl::Crypto::V1::SHA256).derive_key(secret, info: VERSION_2_KEY_PURPOSE, bytesize: 32)
    end

    private def try_verify_and_decrypt(value : Bytes, enc_key : String, sign_key : String) : Bytes?
      signature = value[value.size - @signature_size, @signature_size]
      data_iv = value[0, value.size - @signature_size]
      computed_sig = MessageAuthentication.authentication_tag(@digest, sign_key, data_iv)
      if Crypto::Subtle.constant_time_compare(computed_sig, signature)
        decrypt_with_key(data_iv, enc_key)
      else
        nil
      end
    rescue
      nil
    end

    # Decrypts a version 1 body: ciphertext, then its initialization vector.
    # The cipher takes the first 32 bytes of *key*, as OpenSSL did.
    private def decrypt_with_key(value : Bytes, key : String) : Bytes
      raise "Version 1 message is too short" if value.size < VERSION_1_BLOCK_BYTESIZE
      raise "Version 1 key is too short" if key.bytesize < VERSION_1_KEY_BYTESIZE

      data = value[0, value.size - VERSION_1_BLOCK_BYTESIZE]
      iv = value[value.size - VERSION_1_BLOCK_BYTESIZE, VERSION_1_BLOCK_BYTESIZE]
      cipher = Amber::Beryl::Crypto::Compatibility::AESCBC.new(key.to_slice[0, VERSION_1_KEY_BYTESIZE])
      cipher.decrypt(data, initialization_vector: iv) || raise "Version 1 message does not decrypt"
    end

    # Derives a purpose-specific key from the master secret using HMAC-SHA256.
    # This ensures that the encryption key and signing key are different even
    # when derived from the same master secret. (Format version 1.)
    private def derive_key(secret : String, purpose : String) : String
      derived = MessageAuthentication.authentication_tag(:sha256, secret, purpose)
      # Return the derived key as a raw string of bytes (32 bytes for AES-256)
      String.new(derived)
    end
  end
end
