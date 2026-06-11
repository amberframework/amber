require "./decoder"

module Amber
  module WebSockets
    module Decoders
      # JSON decoder for WebSocket messages.
      #
      # This is the default decoder used by `ClientSocket`. It encodes and decodes
      # messages as JSON strings, which is the standard format for Amber WebSocket
      # communication.
      #
      # Example:
      #
      # ```
      # decoder = Amber::WebSockets::Decoders::JsonDecoder.new
      # decoded = decoder.decode(%|{"event":"message","topic":"room:1"}|)
      # decoded["event"].as_s # => "message"
      #
      # encoded = decoder.encode({"event" => "message", "topic" => "room:1"})
      # # => "{\"event\":\"message\",\"topic\":\"room:1\"}"
      # ```
      class JsonDecoder < Decoder
        def decode(raw : String) : JSON::Any
          JSON.parse(raw)
        rescue ex : JSON::ParseException
          raise DecoderError.new("Failed to decode JSON message: #{ex.message}", raw)
        end

        def encode(payload : Hash) : String
          payload.to_json
        end

        def encode(payload : JSON::Any) : String
          payload.to_json
        end

        def content_type : String
          "application/json"
        end
      end
    end
  end
end
