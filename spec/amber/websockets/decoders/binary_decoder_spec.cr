require "../../../spec_helper"

module Amber
  describe WebSockets::Decoders::BinaryDecoder do
    describe "#encode and #decode" do
      it "round-trips a Hash through encode and decode" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        original = {"event" => "message", "topic" => "room:1", "payload" => "hello"}

        encoded = decoder.encode(original)
        decoded = decoder.decode(encoded)

        decoded["event"].as_s.should eq "message"
        decoded["topic"].as_s.should eq "room:1"
        decoded["payload"].as_s.should eq "hello"
      end

      it "handles empty values" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        original = {"key" => "", "other" => "value"}

        encoded = decoder.encode(original)
        decoded = decoder.decode(encoded)

        decoded["key"].as_s.should eq ""
        decoded["other"].as_s.should eq "value"
      end

      it "handles unicode characters" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        original = {"greeting" => "hello world"}

        encoded = decoder.encode(original)
        decoded = decoder.decode(encoded)

        decoded["greeting"].as_s.should eq "hello world"
      end

      it "handles a single field" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        original = {"only_key" => "only_value"}

        encoded = decoder.encode(original)
        decoded = decoder.decode(encoded)

        decoded["only_key"].as_s.should eq "only_value"
      end
    end

    describe "#decode" do
      it "raises DecoderError for invalid Base64" do
        decoder = WebSockets::Decoders::BinaryDecoder.new

        expect_raises(WebSockets::Decoders::DecoderError, /Failed to decode binary/) do
          decoder.decode("!!!not-base64!!!")
        end
      end

      it "raises DecoderError for truncated binary data" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        # Create data that is too short (just 2 bytes instead of 4 for the field count)
        truncated = Base64.strict_encode(Bytes[0, 1])

        expect_raises(WebSockets::Decoders::DecoderError, /Failed to decode binary/) do
          decoder.decode(truncated)
        end
      end
    end

    describe "#decode with hostile length prefixes" do
      it "rejects a length prefix larger than the message without allocating it" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        # One field whose key claims 4 GiB - 1 bytes but carries none.
        hostile = Base64.strict_encode(Bytes[0, 0, 0, 1, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0])

        allocated = bytes_allocated_by do
          expect_raises(WebSockets::Decoders::DecoderError, /length prefix/) do
            decoder.decode(hostile)
          end
        end
        allocated.should be < 1_048_576_u64
      end

      it "rejects a field count the message cannot hold" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        hostile = Base64.strict_encode(Bytes[0xFF, 0xFF, 0xFF, 0xFF])

        expect_raises(WebSockets::Decoders::DecoderError, /field count/) do
          decoder.decode(hostile)
        end
      end
    end

    describe "#encode with JSON::Any" do
      it "encodes a JSON::Any object" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        payload = JSON.parse(%|{"event":"test","data":"value"}|)

        encoded = decoder.encode(payload)
        decoded = decoder.decode(encoded)

        # JSON::Any#to_s produces the JSON representation of the value,
        # so string values include surrounding quotes
        decoded.as_h.has_key?("event").should be_true
        decoded.as_h.has_key?("data").should be_true
      end
    end

    describe "#content_type" do
      it "returns application/octet-stream" do
        decoder = WebSockets::Decoders::BinaryDecoder.new
        decoder.content_type.should eq "application/octet-stream"
      end
    end
  end
end
