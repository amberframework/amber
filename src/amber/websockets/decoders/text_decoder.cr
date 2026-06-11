require "./decoder"

module Amber
  module WebSockets
    module Decoders
      # Plain text decoder for WebSocket messages.
      #
      # This decoder treats messages as plain text strings. It wraps the raw
      # text in a JSON structure with an "event" field set to "message" and the
      # raw text placed in the "payload" field, making it compatible with the
      # channel dispatch system.
      #
      # This is useful for simple text-based protocols or when clients send
      # unstructured text messages.
      #
      # Example:
      #
      # ```
      # decoder = Amber::WebSockets::Decoders::TextDecoder.new
      # decoded = decoder.decode("hello world")
      # decoded["event"].as_s   # => "message"
      # decoded["payload"].as_s # => "hello world"
      #
      # encoded = decoder.encode({"event" => "message", "payload" => "hello"})
      # # => "{\"event\":\"message\",\"payload\":\"hello\"}"
      # ```
      class TextDecoder < Decoder
        def decode(raw : String) : JSON::Any
          # First try to parse as JSON in case the text is actually JSON
          begin
            return JSON.parse(raw)
          rescue JSON::ParseException
            # Not JSON, wrap in a standard message structure
          end

          wrapped = JSON::Any.new({
            "event"   => JSON::Any.new("message"),
            "topic"   => JSON::Any.new(""),
            "payload" => JSON::Any.new(raw),
          })
          wrapped
        end

        def encode(payload : Hash) : String
          payload.to_json
        end

        def encode(payload : JSON::Any) : String
          payload.to_json
        end

        def content_type : String
          "text/plain"
        end
      end
    end
  end
end
