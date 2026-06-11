require "../../../spec_helper"

module Amber
  describe WebSockets::Decoders::JsonDecoder do
    describe "#decode" do
      it "decodes a valid JSON string" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        raw = %|{"event":"message","topic":"room:1","payload":{"text":"hello"}}|
        result = decoder.decode(raw)

        result["event"].as_s.should eq "message"
        result["topic"].as_s.should eq "room:1"
        result["payload"]["text"].as_s.should eq "hello"
      end

      it "decodes a simple JSON object" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        raw = %|{"key":"value"}|
        result = decoder.decode(raw)

        result["key"].as_s.should eq "value"
      end

      it "raises DecoderError for invalid JSON" do
        decoder = WebSockets::Decoders::JsonDecoder.new

        expect_raises(WebSockets::Decoders::DecoderError, /Failed to decode JSON/) do
          decoder.decode("not valid json {{{")
        end
      end

      it "preserves the raw message in the error" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        raw = "broken json"

        begin
          decoder.decode(raw)
          fail "Expected DecoderError"
        rescue ex : WebSockets::Decoders::DecoderError
          ex.raw_message.should eq raw
        end
      end
    end

    describe "#encode" do
      it "encodes a Hash to JSON string" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        result = decoder.encode({"event" => "message", "topic" => "room:1"})
        parsed = JSON.parse(result)

        parsed["event"].as_s.should eq "message"
        parsed["topic"].as_s.should eq "room:1"
      end

      it "encodes a JSON::Any to JSON string" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        payload = JSON.parse(%|{"key":"value"}|)
        result = decoder.encode(payload)
        parsed = JSON.parse(result)

        parsed["key"].as_s.should eq "value"
      end
    end

    describe "#content_type" do
      it "returns application/json" do
        decoder = WebSockets::Decoders::JsonDecoder.new
        decoder.content_type.should eq "application/json"
      end
    end
  end
end
