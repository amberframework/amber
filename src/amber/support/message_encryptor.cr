require "json"
require "openssl/cipher"
require "openssl/hmac"
require "crypto/subtle"

require "./message_verifier"

module Amber::Support
  class MessageEncryptor
    getter verifier : MessageVerifier

    def initialize(@secret : String, @cipher_algorithm = "aes-256-cbc", @digest = :sha256)
      @verifier = MessageVerifier.new(@secret, digest: @digest)
      @block_size = 16
      @signature_size = 32
    end

    # Verify and Decrypt a message. We need to verify the message in order to
    # avoid padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def verify_and_decrypt(value : Bytes) : Bytes
      signature = value[value.size - @signature_size, @signature_size]
      data_iv = value[0, value.size - @signature_size]
      if Crypto::Subtle.constant_time_compare(sign_bytes(data_iv), signature)
        decrypt(data_iv)
      else
        raise "Invalid Encryption!"
      end
    end

    # Encrypt and sign a message. We need to sign the message in order to avoid
    # padding attacks. Reference: http://www.limited-entropy.com/padding-oracle-attacks.
    def encrypt_and_sign(value)
      encrypt(value, sign: true)
    end

    def encrypt(value, sign = false)
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      cipher.encrypt
      cipher.key = @secret
      iv = cipher.random_iv

      encrypted_data = IO::Memory.new
      encrypted_data.write(cipher.update(value))
      encrypted_data.write(cipher.final)
      encrypted_data.write(iv)
      encrypted_data.write(sign_bytes(encrypted_data.to_slice)) if sign
      encrypted_data.to_slice
    end

    def decrypt(value : Bytes)
      cipher = OpenSSL::Cipher.new(@cipher_algorithm)
      data = value[0, value.size - @block_size]
      iv = value[value.size - @block_size, @block_size]

      cipher.decrypt
      cipher.key = @secret
      cipher.iv = iv

      decrypted_data = IO::Memory.new
      decrypted_data.write cipher.update(data)
      decrypted_data.write cipher.final
      decrypted_data.to_slice
    end

    private def sign_bytes(data : Bytes)
      OpenSSL::HMAC.digest(@digest, @secret, data)
    end
  end
end
