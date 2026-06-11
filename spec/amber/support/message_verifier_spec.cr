require "../../spec_helper"

module Amber::Support
  describe MessageVerifier do
    describe "basic signing and verification" do
      it "generates and verifies a signed message" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        signed = verifier.generate("hello")
        verified = verifier.verify(signed)

        verified.should eq("hello")
      end

      it "returns nil for tampered message via verified" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        signed = verifier.generate("hello")
        tampered = signed.sub("--", "--tampered")

        verifier.verified(tampered).should be_nil
      end

      it "raises for tampered message via verify" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        signed = verifier.generate("hello")
        tampered = signed.sub("--", "--tampered")

        expect_raises(Amber::Exceptions::InvalidSignature) do
          verifier.verify(tampered)
        end
      end
    end

    describe "default digest is SHA256" do
      it "defaults to SHA256" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        signed = verifier.generate("test")
        verified = verifier.verify(signed)
        verified.should eq("test")
      end

      it "SHA256 verifier cannot verify SHA1 signed messages" do
        secret = Random::Secure.urlsafe_base64(32)
        sha1_verifier = MessageVerifier.new(secret, digest: :sha1)
        sha256_verifier = MessageVerifier.new(secret, digest: :sha256)

        signed_sha1 = sha1_verifier.generate("test")
        sha256_verifier.verified(signed_sha1).should be_nil
      end

      it "allows specifying SHA1 digest explicitly" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret, digest: :sha1)

        signed = verifier.generate("test")
        verified = verifier.verify(signed)
        verified.should eq("test")
      end
    end

    describe "key rotation support" do
      it "verifies with current secret" do
        current = Random::Secure.urlsafe_base64(32)
        old = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(current, previous_secrets: [old])

        signed = verifier.generate("current data")
        verified = verifier.verify(signed)

        verified.should eq("current data")
      end

      it "verifies messages signed with a previous secret" do
        old_secret = Random::Secure.urlsafe_base64(32)
        new_secret = Random::Secure.urlsafe_base64(32)

        # Sign with old verifier
        old_verifier = MessageVerifier.new(old_secret)
        signed = old_verifier.generate("old data")

        # Verify with new verifier that knows about old secret
        new_verifier = MessageVerifier.new(new_secret, previous_secrets: [old_secret])
        verified = new_verifier.verified(signed)

        verified.should eq("old data")
      end

      it "always signs with the current secret" do
        current = Random::Secure.urlsafe_base64(32)
        old = Random::Secure.urlsafe_base64(32)

        verifier_with_rotation = MessageVerifier.new(current, previous_secrets: [old])
        verifier_current_only = MessageVerifier.new(current)

        signed = verifier_with_rotation.generate("new data")

        # Current-only verifier should be able to verify it
        verified = verifier_current_only.verify(signed)
        verified.should eq("new data")
      end

      it "tries multiple previous secrets" do
        oldest = Random::Secure.urlsafe_base64(32)
        older = Random::Secure.urlsafe_base64(32)
        current = Random::Secure.urlsafe_base64(32)

        # Sign with oldest key
        oldest_verifier = MessageVerifier.new(oldest)
        signed = oldest_verifier.generate("very old data")

        # New verifier should find it in rotation chain
        new_verifier = MessageVerifier.new(current, previous_secrets: [older, oldest])
        verified = new_verifier.verified(signed)

        verified.should eq("very old data")
      end

      it "returns nil when no secret can verify" do
        secret1 = Random::Secure.urlsafe_base64(32)
        secret2 = Random::Secure.urlsafe_base64(32)
        secret3 = Random::Secure.urlsafe_base64(32)

        verifier1 = MessageVerifier.new(secret1)
        signed = verifier1.generate("data")

        verifier2 = MessageVerifier.new(secret2, previous_secrets: [secret3])
        verifier2.verified(signed).should be_nil
      end

      it "raises via verify when no secret can verify" do
        secret1 = Random::Secure.urlsafe_base64(32)
        secret2 = Random::Secure.urlsafe_base64(32)

        verifier1 = MessageVerifier.new(secret1)
        signed = verifier1.generate("data")

        verifier2 = MessageVerifier.new(secret2)
        expect_raises(Amber::Exceptions::InvalidSignature) do
          verifier2.verify(signed)
        end
      end

      it "verify_raw works with key rotation" do
        old_secret = Random::Secure.urlsafe_base64(32)
        new_secret = Random::Secure.urlsafe_base64(32)

        old_verifier = MessageVerifier.new(old_secret)
        signed = old_verifier.generate("raw data")

        new_verifier = MessageVerifier.new(new_secret, previous_secrets: [old_secret])
        result = String.new(new_verifier.verify_raw(signed))
        result.should eq("raw data")
      end
    end

    describe "valid_message?" do
      it "returns true for valid data and digest" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        signed = verifier.generate("test")
        data, digest = signed.split("--")
        verifier.valid_message?(data, digest).should be_true
      end

      it "returns false for empty data" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        verifier.valid_message?("", "some_digest").should be_false
      end

      it "returns false for empty digest" do
        secret = Random::Secure.urlsafe_base64(32)
        verifier = MessageVerifier.new(secret)

        verifier.valid_message?("some_data", "").should be_false
      end
    end
  end
end
