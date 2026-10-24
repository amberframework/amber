module Amber
  module WebSockets
    # A WebSocket protocol reader that caps how many bytes one message may
    # accumulate while its frames and fragments arrive.
    #
    # Crystal's `HTTP::WebSocket` reads each frame in 4 KiB blocks and joins
    # fragments into one message. This reader counts the payload bytes of
    # the data message being assembled (text, binary, and continuation
    # frames) and, separately, of a control frame, as each block arrives.
    # When a count passes *max_message_bytes* it sends a close frame with
    # code 1009 (message too big) and stops reading, so an oversized message
    # is never assembled.
    class BoundedProtocol < HTTP::WebSocket::Protocol
      getter max_message_bytes : Int64

      @data_message_bytes = 0_i64
      @control_frame_bytes = 0_i64

      def initialize(io : IO, max_message_bytes : Int, sync_close = true)
        @max_message_bytes = max_message_bytes.to_i64
        super(io, sync_close: sync_close)
      end

      def receive(buffer : Bytes) : HTTP::WebSocket::Protocol::PacketInfo
        info = super
        opcode = info.opcode

        if opcode.ping? || opcode.pong? || opcode.close?
          @control_frame_bytes += info.size
          reject_oversized_message if @control_frame_bytes > @max_message_bytes
          @control_frame_bytes = 0_i64 if info.final
        else
          @data_message_bytes += info.size
          reject_oversized_message if @data_message_bytes > @max_message_bytes
          @data_message_bytes = 0_i64 if info.final
        end
        info
      end

      private def reject_oversized_message : NoReturn
        close(HTTP::WebSocket::CloseCode::MessageTooBig, "Message exceeds #{@max_message_bytes} bytes")
        raise IO::Error.new("WebSocket message exceeds #{@max_message_bytes} bytes")
      end
    end
  end
end
