require "json"
require "openssl/cipher"
require "openssl/hmac"
require "crypto/subtle"

require "./message_verifier"

module Amber::Support
  class MessageEncryptor
    Log = ::Log.for(self)

    getter verifier : MessageVerifier

    @encryption_key : String
    @signing_key : String
    @previous_secrets : Array(String)

    def initialize(@secret : String, @cipher_algorithm = "aes-256-cbc", @digest = :sha256,
                   @previous_secrets = [] of String)
      @encryption_key = derive_key(@secret, "amber.encryption")
      @signing_key = derive_key(@secret, "amber.signing")
      @verifier = MessageVerifier.new(@signing_key, digest: @digest)
      @block_size = 16
      @signature_size = 32
    end

    # Verify and Decrypt a message. We need to verify the message in order to
    # avoid padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def verify_and_decrypt(value : Bytes) : Bytes
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

    # Encrypt and sign a message. We need to sign the message in order to avoid
    # padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def encrypt_and_sign(value)
      encrypt(value, sign: true)
    end

    def encrypt(value, sign = false)
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      cipher.encrypt
      cipher.key = @encryption_key
      iv = cipher.random_iv

      encrypted_data = IO::Memory.new
      encrypted_data.write(cipher.update(value))
      encrypted_data.write(cipher.final)
      encrypted_data.write(iv)
      encrypted_data.write(sign_bytes(encrypted_data.to_slice)) if sign
      encrypted_data.to_slice
    end

    def decrypt(value : Bytes)
      decrypt_with_key(value, @encryption_key)
    end

    private def try_verify_and_decrypt(value : Bytes, enc_key : String, sign_key : String) : Bytes?
      signature = value[value.size - @signature_size, @signature_size]
      data_iv = value[0, value.size - @signature_size]
      computed_sig = OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(@digest.to_s), sign_key, data_iv)
      if Crypto::Subtle.constant_time_compare(computed_sig, signature)
        decrypt_with_key(data_iv, enc_key)
      else
        nil
      end
    rescue
      nil
    end

    private def decrypt_with_key(value : Bytes, key : String) : Bytes
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      data = value[0, value.size - @block_size]
      iv = value[value.size - @block_size, @block_size]

      cipher.decrypt
      cipher.key = key
      cipher.iv = iv

      decrypted_data = IO::Memory.new
      decrypted_data.write cipher.update(data)
      decrypted_data.write cipher.final
      decrypted_data.to_slice
    end

    private def sign_bytes(data : Bytes)
      OpenSSL::HMAC.digest(OpenSSL::Algorithm.parse(@digest.to_s), @signing_key, data)
    end

    # Derives a purpose-specific key from the master secret using HMAC-SHA256.
    # This ensures that the encryption key and signing key are different even
    # when derived from the same master secret.
    private def derive_key(secret : String, purpose : String) : String
      derived = OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, secret, purpose)
      # Return the derived key as a raw string of bytes (32 bytes for AES-256)
      String.new(derived)
    end
  end
end
