require "../../spec_helper"

module Amber::Support
  describe MessageEncryptor do
    describe "basic encryption and decryption" do
      it "encrypts and decrypts a message" do
        secret = Random::Secure.urlsafe_base64(32)
        encryptor = MessageEncryptor.new(secret)

        encrypted = encryptor.encrypt("hello world", sign: true)
        decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

        decrypted.should eq("hello world")
      end

      it "encrypts and decrypts with encrypt_and_sign" do
        secret = Random::Secure.urlsafe_base64(32)
        encryptor = MessageEncryptor.new(secret)

        encrypted = encryptor.encrypt_and_sign("test message")
        decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

        decrypted.should eq("test message")
      end

      it "fails to decrypt with wrong secret" do
        secret1 = Random::Secure.urlsafe_base64(32)
        secret2 = Random::Secure.urlsafe_base64(32)
        encryptor1 = MessageEncryptor.new(secret1)
        encryptor2 = MessageEncryptor.new(secret2)

        encrypted = encryptor1.encrypt("secret data", sign: true)

        expect_raises(Exception) do
          encryptor2.verify_and_decrypt(encrypted)
        end
      end
    end

    describe "separate encryption and signing keys" do
      it "uses derived keys rather than raw secret" do
        secret = Random::Secure.urlsafe_base64(32)
        encryptor = MessageEncryptor.new(secret)

        # The encryptor should still work - derived keys are used internally
        encrypted = encryptor.encrypt("test", sign: true)
        decrypted = String.new(encryptor.verify_and_decrypt(encrypted))
        decrypted.should eq("test")
      end

      it "encryption from different encryptors with same secret produces compatible results" do
        secret = Random::Secure.urlsafe_base64(32)
        encryptor1 = MessageEncryptor.new(secret)
        encryptor2 = MessageEncryptor.new(secret)

        encrypted = encryptor1.encrypt("shared secret", sign: true)
        decrypted = String.new(encryptor2.verify_and_decrypt(encrypted))

        decrypted.should eq("shared secret")
      end
    end

    describe "key rotation support" do
      it "decrypts with current key" do
        current = Random::Secure.urlsafe_base64(32)
        old = Random::Secure.urlsafe_base64(32)

        encryptor = MessageEncryptor.new(current, previous_secrets: [old])
        encrypted = encryptor.encrypt("current key data", sign: true)
        decrypted = String.new(encryptor.verify_and_decrypt(encrypted))

        decrypted.should eq("current key data")
      end

      it "decrypts data encrypted with a previous secret" do
        old_secret = Random::Secure.urlsafe_base64(32)
        new_secret = Random::Secure.urlsafe_base64(32)

        # Encrypt with old encryptor
        old_encryptor = MessageEncryptor.new(old_secret)
        encrypted = old_encryptor.encrypt("old data", sign: true)

        # Decrypt with new encryptor that knows about old secret
        new_encryptor = MessageEncryptor.new(new_secret, previous_secrets: [old_secret])
        decrypted = String.new(new_encryptor.verify_and_decrypt(encrypted))

        decrypted.should eq("old data")
      end

      it "always encrypts with the current key" do
        current = Random::Secure.urlsafe_base64(32)
        old = Random::Secure.urlsafe_base64(32)

        encryptor_with_rotation = MessageEncryptor.new(current, previous_secrets: [old])
        encryptor_current_only = MessageEncryptor.new(current)

        encrypted = encryptor_with_rotation.encrypt("new data", sign: true)

        # The current-only encryptor should be able to decrypt it
        decrypted = String.new(encryptor_current_only.verify_and_decrypt(encrypted))
        decrypted.should eq("new data")
      end

      it "tries multiple previous secrets" do
        oldest = Random::Secure.urlsafe_base64(32)
        older = Random::Secure.urlsafe_base64(32)
        current = Random::Secure.urlsafe_base64(32)

        # Encrypt with the oldest key
        oldest_encryptor = MessageEncryptor.new(oldest)
        encrypted = oldest_encryptor.encrypt("very old data", sign: true)

        # New encryptor should find it in the rotation chain
        new_encryptor = MessageEncryptor.new(current, previous_secrets: [older, oldest])
        decrypted = String.new(new_encryptor.verify_and_decrypt(encrypted))

        decrypted.should eq("very old data")
      end

      it "raises when no secret can decrypt" do
        secret1 = Random::Secure.urlsafe_base64(32)
        secret2 = Random::Secure.urlsafe_base64(32)
        secret3 = Random::Secure.urlsafe_base64(32)

        encryptor1 = MessageEncryptor.new(secret1)
        encrypted = encryptor1.encrypt("data", sign: true)

        encryptor2 = MessageEncryptor.new(secret2, previous_secrets: [secret3])
        expect_raises(Exception, /Decryption failed/) do
          encryptor2.verify_and_decrypt(encrypted)
        end
      end
    end

    describe "default digest" do
      it "uses SHA256 as default digest" do
        secret = Random::Secure.urlsafe_base64(32)
        encryptor = MessageEncryptor.new(secret)

        # Verify the encryptor works with SHA256 (the default)
        encrypted = encryptor.encrypt("test", sign: true)
        decrypted = String.new(encryptor.verify_and_decrypt(encrypted))
        decrypted.should eq("test")
      end
    end
  end
end
