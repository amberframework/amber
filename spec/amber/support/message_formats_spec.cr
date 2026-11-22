require "../../spec_helper"

# Messages written by Amber 2.0.0-beta.13, whose MessageEncryptor,
# MessageVerifier and COSE ran on OpenSSL (AES-256-CBC, HMAC and
# ChaCha20-Poly1305 from libcrypto). They were captured before the move to
# Beryl and must be read, byte for byte, for as long as such values exist
# in cookies and files.
private module MessagesWrittenOnOpenSSL
  SECRET      = "c2VjcmV0LWtleS1mb3ItYW1iZXItZml4dHVyZXMtMDEyMzQ1Njc4OQ" # secret-scan-gate:allow (a key or value made for this spec)
  OLD_SECRET  = "b2xkLXNlY3JldC1rZXktZm9yLWFtYmVyLWZpeHR1cmVzLTk4NzY1NA" # secret-scan-gate:allow (a key or value made for this spec)
  PLAINTEXT   = "session={\"user_id\":42,\"csrf\":\"x9\"}; a longer value that spans blocks"
  SIGNED_TEXT = "flash:notice=saved"

  VERSION_1_SIGNED                  = "VHxzUFd2w+s9S4ND48vMZ+ZLm0aRMcPkUvbFMcW57ZzQ/chB+4GuTgwGEu8PkbnVLyyr5L7ah/YdUGyQKI3XOt86eVZp1HAUkZasKRpyI7NM4RSuVh2J0X4+/BFyhGH6f+MLRJug2DqoDw3m4pxZAoWZKgvFlRub62jVPeFqdL8="
  VERSION_1_UNSIGNED                = "Lm5ONJlkj3COSAiiAWVNfrJX+wNmSds7s+DCxYwAZ1+4dpdkzGEx5K/ybXxjV+KCIfVvPcLD4sB11ZYINZirFBVnkcvS6fn3ZY1iWmLMJWlnZzMQRs+JLNgZ6mVqK/qg"
  VERSION_1_SIGNED_EMPTY            = "wJmMFiiCj8/oFahT2+4wRyIDfOienqO2GBrnQWbnDn4xffuVCu9PtGLci/tgWgu8uKGjTM92D2HZ553SKyGmjA=="
  VERSION_1_SIGNED_UNDER_OLD_SECRET = "hlwn5BPuz+BArDW/lhSjSIbEknFpH28w2yRwzp5P2zyEH1HHGCkUDBMGhNstZjZGtsh4MYyt3UeMVw+mL3Otyzxc2Nf0DsIzbcEq+BdvspvqpbT22NqLLM5QaUn2l7HNIOg8EHiLUeoqjR+LIzLjkV5rbcZDob+MbOXdbz7HZAE=" # secret-scan-gate:allow (a key or value made for this spec)
  VERSION_1_LEGACY_SINGLE_KEY       = "uaCj5DwSBIZfosVGN/GPczu6ftx3oH42j+J1zFounf7eRfj7xZaFrz/FqkE4q4yrXxgZiEXKFFT/H0Ay+1wxHZaIV+03MO+Bt+I0patUcLjeN96evkeOq7G54jXPbDBhh3fbOFWvD9HpZ2OtbMqwNc/mM/gAIo0RmxSeHOkobE0="

  SIGNED_WITH_SHA256      = "Zmxhc2g6bm90aWNlPXNhdmVk--NRTLCNp0DKMTuZoS/yfflHprruNfS1GcfEv2P5we5rE="
  SIGNED_WITH_SHA384      = "Zmxhc2g6bm90aWNlPXNhdmVk--v5e+EE7ipTQ6MdoXu6oBPwGD/XfigRAFYMDpmbQhs10+5tQM49KQuo8cuZ9xaJEK"
  SIGNED_WITH_SHA512      = "Zmxhc2g6bm90aWNlPXNhdmVk--l9YSsKCpHGTt3pj/zpW4jn9VJWHCiy9yZF4Fhq5RikF5Dmam+fxIR3lQ2FDPBOkcGE48MPlzxlE0yk+NIsecyA=="
  SIGNED_UNDER_OLD_SECRET = "Zmxhc2g6bm90aWNlPXNhdmVk--K2cYfTr9kzIrSgiEVwly7YYEqhOnKSHOPYyGWr2IchE=" # secret-scan-gate:allow (a key or value made for this spec)

  COSE_KEY     = Bytes.new(32) { |index| (index * 5 + 1).to_u8 }
  COSE_MESSAGE = "0INEoQEYGKIES2ZpeHR1cmUta2V5BUwkxswMFSCh0e8twt5YISLHKuCD+GGNNxYcKqNiG90UYemsXyYBQc2rUZHPU+4LFA=="
  COSE_SEALED  = "06ed663d003e2df4dd670a359db5749b26ee419a7dbf0f36992c02957f5bc6d12711ba"
end

module Amber::Support
  describe MessageEncryptor do
    describe "format version 2" do
      it "writes the AMB2 header, a 24-byte nonce, the ciphertext and a 16-byte tag" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        sealed = encryptor.encrypt_and_sign("hello world")

        String.new(sealed[0, 4]).should eq("AMB2")
        sealed.size.should eq(4 + 24 + 11 + 16)
        String.new(encryptor.verify_and_decrypt(sealed)).should eq("hello world")
      end

      it "is XChaCha20-Poly1305 under an HKDF-SHA256 key, with the header authenticated" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        sealed = encryptor.encrypt_and_sign("hello world")

        key = Amber::Beryl::Crypto::V1::HKDF(Amber::Beryl::Crypto::V1::SHA256).derive_key(
          MessagesWrittenOnOpenSSL::SECRET, info: "amber message encryptor v2", bytesize: 32
        )
        cipher = Amber::Beryl::Crypto::V1::XChaCha20Poly1305.new(key)
        opened = cipher.decrypt(sealed[28, sealed.size - 28], nonce: sealed[4, 24], associated_data: "AMB2".to_slice)
        opened.should eq("hello world".to_slice)
      end

      it "draws a new nonce for every message" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        encryptor.encrypt_and_sign("same").should_not eq(encryptor.encrypt_and_sign("same"))
      end

      it "writes an authenticated message whether or not sign is given" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        sealed = encryptor.encrypt("unsigned call")
        String.new(sealed[0, 4]).should eq("AMB2")
        String.new(encryptor.decrypt(sealed)).should eq("unsigned call")
        String.new(encryptor.verify_and_decrypt(sealed)).should eq("unsigned call")
      end

      it "refuses a message with any byte changed" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        sealed = encryptor.encrypt_and_sign("tamper with me")
        sealed.size.times do |position|
          altered = sealed.dup
          altered[position] ^= 0x01_u8
          expect_raises(Exception, "Decryption failed") { encryptor.verify_and_decrypt(altered) }
        end
      end

      it "reads a message written under a previous secret" do
        sealed = MessageEncryptor.new(MessagesWrittenOnOpenSSL::OLD_SECRET).encrypt_and_sign("rotated")
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET, previous_secrets: [MessagesWrittenOnOpenSSL::OLD_SECRET])
        String.new(encryptor.verify_and_decrypt(sealed)).should eq("rotated")

        expect_raises(Exception, "Decryption failed") do
          MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET).verify_and_decrypt(sealed)
        end
      end

      it "encrypts an empty message" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        encryptor.verify_and_decrypt(encryptor.encrypt_and_sign("")).should eq(Bytes.empty)
      end
    end

    describe "format version 1, written on OpenSSL" do
      it "reads a signed message" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        opened = encryptor.verify_and_decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_SIGNED))
        String.new(opened).should eq(MessagesWrittenOnOpenSSL::PLAINTEXT)
      end

      it "reads a signed empty message" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        encryptor.verify_and_decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_SIGNED_EMPTY)).should eq(Bytes.empty)
      end

      it "reads a message signed under a previous secret" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET, previous_secrets: [MessagesWrittenOnOpenSSL::OLD_SECRET])
        opened = encryptor.verify_and_decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_SIGNED_UNDER_OLD_SECRET))
        String.new(opened).should eq(MessagesWrittenOnOpenSSL::PLAINTEXT)
      end

      it "reads the legacy single-key form" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        opened = encryptor.verify_and_decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_LEGACY_SINGLE_KEY))
        String.new(opened).should eq(MessagesWrittenOnOpenSSL::PLAINTEXT)
      end

      it "reads an unsigned message through decrypt" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        opened = encryptor.decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_UNSIGNED))
        String.new(opened).should eq(MessagesWrittenOnOpenSSL::PLAINTEXT)
      end

      it "refuses a signed message with any byte changed, and one under another secret" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        sealed = Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_SIGNED)
        sealed.size.times do |position|
          altered = sealed.dup
          altered[position] ^= 0x01_u8
          expect_raises(Exception, "Decryption failed") { encryptor.verify_and_decrypt(altered) }
        end
        expect_raises(Exception, "Decryption failed") do
          MessageEncryptor.new(MessagesWrittenOnOpenSSL::OLD_SECRET).verify_and_decrypt(sealed)
        end
      end

      it "rewrites a version 1 message in version 2 with the same contents" do
        encryptor = MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET)
        opened = encryptor.verify_and_decrypt(Base64.decode(MessagesWrittenOnOpenSSL::VERSION_1_SIGNED))
        rewritten = encryptor.encrypt_and_sign(opened)
        String.new(rewritten[0, 4]).should eq("AMB2")
        encryptor.verify_and_decrypt(rewritten).should eq(opened)
      end
    end

    describe ".new" do
      it "raises ArgumentError for a version 1 cipher other than aes-256-cbc" do
        expect_raises(ArgumentError, "aes-256-cbc") do
          MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET, "aes-128-cbc")
        end
      end

      it "raises ArgumentError for a digest outside the supported set" do
        expect_raises(ArgumentError, ":sha256, :sha384, :sha512, :sha1") do
          MessageEncryptor.new(MessagesWrittenOnOpenSSL::SECRET, digest: :md5)
        end
      end
    end
  end

  describe MessageVerifier do
    describe "messages signed on OpenSSL" do
      it "verifies SHA-256, SHA-384 and SHA-512 signatures and writes the same bytes" do
        {
          :sha256 => MessagesWrittenOnOpenSSL::SIGNED_WITH_SHA256,
          :sha384 => MessagesWrittenOnOpenSSL::SIGNED_WITH_SHA384,
          :sha512 => MessagesWrittenOnOpenSSL::SIGNED_WITH_SHA512,
        }.each do |digest, signed_message|
          verifier = MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, digest: digest)
          verifier.verify(signed_message).should eq(MessagesWrittenOnOpenSSL::SIGNED_TEXT)
          verifier.generate(MessagesWrittenOnOpenSSL::SIGNED_TEXT).should eq(signed_message)
        end
      end

      it "verifies a message signed under a previous secret" do
        verifier = MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, previous_secrets: [MessagesWrittenOnOpenSSL::OLD_SECRET])
        verifier.verify(MessagesWrittenOnOpenSSL::SIGNED_UNDER_OLD_SECRET).should eq(MessagesWrittenOnOpenSSL::SIGNED_TEXT)
      end
    end

    describe ".new" do
      it "accepts the digest as a Symbol or a String in any letter case" do
        signed_message = MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, digest: "SHA256").generate("x")
        MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, digest: :sha256).verify(signed_message).should eq("x")
      end

      it "raises ArgumentError, naming the supported digests, for any other" do
        expect_raises(ArgumentError, ":sha256, :sha384, :sha512, :sha1") do
          MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, digest: :md4)
        end
        expect_raises(ArgumentError, "ripemd160") do
          MessageVerifier.new(MessagesWrittenOnOpenSSL::SECRET, digest: :ripemd160)
        end
      end
    end
  end
end

describe Amber::Schema::COSE do
  describe "messages written on OpenSSL" do
    it "opens a COSE_Encrypt0 message" do
      provider = Amber::Schema::COSE::KeyProvider.new(MessagesWrittenOnOpenSSL::COSE_KEY, "fixture-key")
      message = Base64.decode(MessagesWrittenOnOpenSSL::COSE_MESSAGE)
      opened = Amber::Schema::COSE.decrypt0(IO::Memory.new(message), provider, "aad-1".to_slice)
      String.new(opened).should eq(%({"title":"hello"}))
    end

    it "seals to the same bytes for the same key, nonce, message and associated data" do
      nonce = Bytes.new(12) { |index| index.to_u8 }
      sealed = Amber::Schema::COSE::ChaCha20Poly1305.seal(
        MessagesWrittenOnOpenSSL::COSE_KEY, nonce, "sealed by libcrypto".to_slice, "header".to_slice
      )
      sealed.hexstring.should eq(MessagesWrittenOnOpenSSL::COSE_SEALED)
      opened = Amber::Schema::COSE::ChaCha20Poly1305.open(
        MessagesWrittenOnOpenSSL::COSE_KEY, nonce, MessagesWrittenOnOpenSSL::COSE_SEALED.hexbytes, "header".to_slice
      )
      opened.should eq("sealed by libcrypto".to_slice)
    end

    it "returns nil from open for a message with one bit flipped" do
      nonce = Bytes.new(12) { |index| index.to_u8 }
      altered = MessagesWrittenOnOpenSSL::COSE_SEALED.hexbytes
      altered[3] ^= 0x10_u8
      Amber::Schema::COSE::ChaCha20Poly1305.open(MessagesWrittenOnOpenSSL::COSE_KEY, nonce, altered, "header".to_slice).should be_nil
    end
  end
end
