require "../../../spec_helper"

module Amber
  describe WebSockets::Decoders::TextDecoder do
    describe "#decode" do
      it "wraps plain text in a message structure" do
        decoder = WebSockets::Decoders::TextDecoder.new
        result = decoder.decode("hello world")

        result["event"].as_s.should eq "message"
        result["payload"].as_s.should eq "hello world"
        result["topic"].as_s.should eq ""
      end

      it "passes through valid JSON unchanged" do
        decoder = WebSockets::Decoders::TextDecoder.new
        raw = %|{"event":"join","topic":"room:1"}|
        result = decoder.decode(raw)

        result["event"].as_s.should eq "join"
        result["topic"].as_s.should eq "room:1"
      end

      it "wraps empty string in a message structure" do
        decoder = WebSockets::Decoders::TextDecoder.new
        result = decoder.decode("")

        result["event"].as_s.should eq "message"
        result["payload"].as_s.should eq ""
      end

      it "handles text with special characters" do
        decoder = WebSockets::Decoders::TextDecoder.new
        result = decoder.decode("hello <world> & \"friends\"")

        result["payload"].as_s.should eq "hello <world> & \"friends\""
      end
    end

    describe "#encode" do
      it "encodes a Hash to JSON string" do
        decoder = WebSockets::Decoders::TextDecoder.new
        result = decoder.encode({"event" => "message", "payload" => "hello"})
        parsed = JSON.parse(result)

        parsed["event"].as_s.should eq "message"
        parsed["payload"].as_s.should eq "hello"
      end

      it "encodes a JSON::Any to JSON string" do
        decoder = WebSockets::Decoders::TextDecoder.new
        payload = JSON.parse(%|{"text":"hello"}|)
        result = decoder.encode(payload)
        parsed = JSON.parse(result)

        parsed["text"].as_s.should eq "hello"
      end
    end

    describe "#content_type" do
      it "returns text/plain" do
        decoder = WebSockets::Decoders::TextDecoder.new
        decoder.content_type.should eq "text/plain"
      end
    end
  end
end
