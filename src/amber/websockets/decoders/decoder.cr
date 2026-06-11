module Amber
  module WebSockets
    module Decoders
      # Abstract base class for WebSocket message decoders.
      #
      # Decoders handle the serialization and deserialization of messages
      # sent over WebSocket connections. The framework ships with JSON, text,
      # and binary decoders, but custom decoders can be created by inheriting
      # from this class.
      #
      # Example:
      #
      # ```
      # class CustomDecoder < Amber::WebSockets::Decoders::Decoder
      #   def decode(raw : String) : JSON::Any
      #     # custom decoding logic
      #   end
      #
      #   def encode(payload) : String
      #     # custom encoding logic
      #   end
      #
      #   def content_type : String
      #     "application/x-custom"
      #   end
      # end
      # ```
      abstract class Decoder
        # Decodes a raw message string into a structured JSON::Any value.
        #
        # Returns a JSON::Any representing the decoded message. Implementations
        # should raise `DecoderError` if the message cannot be decoded.
        abstract def decode(raw : String) : JSON::Any

        # Encodes a Hash payload into a string suitable for sending over the socket.
        abstract def encode(payload : Hash) : String

        # Encodes a JSON::Any payload into a string suitable for sending over the socket.
        abstract def encode(payload : JSON::Any) : String

        # Returns the MIME content type associated with this decoder.
        abstract def content_type : String
      end

      # Raised when a decoder encounters a message it cannot process.
      class DecoderError < Exception
        getter raw_message : String?

        def initialize(message : String, @raw_message : String? = nil)
          super(message)
        end
      end
    end
  end
end
