require "../../spec_helper"

module Amber::Support
  describe MessageVerifier do
    secret = "a" * 32
    verifier = MessageVerifier.new(secret)

    it "signs and verifies valid messages successfully" do
      message = "Hello, world!"
      signed = verifier.generate(message)
      verified = verifier.verified(signed)
      verified.should eq message
    end

    it "returns nil for malformed/no-delimiter payloads in verified" do
      malformed = "invalidpayload"
      verifier.verified(malformed).should be_nil
    end

    it "raises Exceptions::InvalidSignature for malformed/no-delimiter payloads in verify_raw" do
      malformed = "invalidpayload"
      expect_raises(Exceptions::InvalidSignature) do
        verifier.verify_raw(malformed)
      end
    end
  end
end
