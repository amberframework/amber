require "../../spec_helper"

module Amber::Support
  describe MessageEncryptor do
    secret = "a" * 32
    encryptor = MessageEncryptor.new(secret)

    it "encrypts and decrypts valid messages successfully" do
      message = "Hello, world!"
      encrypted = encryptor.encrypt_and_sign(message)
      decrypted = encryptor.verify_and_decrypt(encrypted)
      String.new(decrypted).should eq message
    end

    it "raises Exceptions::InvalidMessage for undersized payloads in verify_and_decrypt" do
      # signature_size is 32, block_size is 16. Total required: >= 48 bytes
      undersized = Bytes.new(20)
      expect_raises(Exceptions::InvalidMessage, "Invalid message size") do
        encryptor.verify_and_decrypt(undersized)
      end
    end

    it "raises Exceptions::InvalidMessage for undersized payloads in decrypt" do
      # block_size is 16. decrypt expects >= 16 bytes
      undersized = Bytes.new(10)
      expect_raises(Exceptions::InvalidMessage, "Invalid message size") do
        encryptor.decrypt(undersized)
      end
    end
  end
end
