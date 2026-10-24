require "../../spec_helper"

# Frames a client would send: masked, with the message split into
# continuation frames of *frame_size* bytes, and optional pings between
# the fragments.
private def client_frames(message : String, frame_size : Int32, ping_every : Int32? = nil) : Bytes
  wire = IO::Memory.new
  client = HTTP::WebSocket::Protocol.new(wire, masked: true)
  if ping_every
    message.each_char.each_slice(frame_size).with_index do |chars, index|
      opcode_text = index == 0
      final = (index + 1) * frame_size >= message.size
      header_io = IO::Memory.new
      header_io << chars.join
      client.ping("p") if index % ping_every == 0 && index > 0
      client.send(header_io.to_slice, opcode_text ? HTTP::WebSocket::Protocol::Opcode::TEXT : HTTP::WebSocket::Protocol::Opcode::CONTINUATION, flags: final ? HTTP::WebSocket::Protocol::Flags::FINAL : HTTP::WebSocket::Protocol::Flags::None)
    end
  else
    client.stream(binary: false, frame_size: frame_size) do |io|
      io << message
    end
  end
  wire.to_slice
end

# Runs a server-side session over *frames* and returns the messages it
# delivered and the bytes it wrote back.
private def serve(frames : Bytes, max_message_bytes : Int) : Tuple(Array(String), Bytes)
  reply = IO::Memory.new
  io = IO::Stapled.new(IO::Memory.new(frames), reply)
  session = HTTP::WebSocket.new(Amber::WebSockets::BoundedProtocol.new(io, max_message_bytes, sync_close: false))
  list_of_messages = [] of String
  session.on_message { |message| list_of_messages << message }
  session.run
  {list_of_messages, reply.to_slice}
end

private def close_code(reply : Bytes) : Int32?
  # Server frames are unmasked: an opcode byte, a length (7 bits, or 126 and
  # 2 bytes, or 127 and 8 bytes), then the payload.
  io = IO::Memory.new(reply)
  while first = io.read_byte
    length = (io.read_byte || return).to_i64 & 0x7F
    length = io.read_bytes(UInt16, IO::ByteFormat::NetworkEndian).to_i64 if length == 126
    length = io.read_bytes(UInt64, IO::ByteFormat::NetworkEndian).to_i64 if length == 127
    if first & 0x0F_u8 == 0x08_u8 && length >= 2
      return io.read_bytes(UInt16, IO::ByteFormat::NetworkEndian).to_i32
    end
    io.skip(length)
  end
  nil
end

module Amber::WebSockets
  describe BoundedProtocol do
    it "delivers a fragmented message within the cap" do
      messages, reply = serve(client_frames("x" * 10_000, 1_024), 16_384)

      messages.should eq ["x" * 10_000]
      reply.size.should eq 0
    end

    it "closes with 1009 while a fragmented message passes the cap, before assembling it" do
      frames = client_frames("x" * 20_000_000, 65_536)

      list_of_results = [] of Tuple(Array(String), Bytes)
      allocated = bytes_allocated_by do
        list_of_results << serve(frames, 65_536)
      end
      messages, reply = list_of_results.first

      messages.should be_empty
      close_code(reply).should eq 1009
      allocated.should be < 4_u64 * 1_048_576
    end

    it "keeps counting a data message across interleaved pings" do
      frames = client_frames("x" * 8_000, 1_000, ping_every: 1)
      messages, reply = serve(frames, 4_096)

      messages.should be_empty
      close_code(reply).should eq 1009
    end
  end

  describe Server::Handler do
    it "upgrades socket routes through a BoundedProtocol that closes oversized messages with 1009" do
      list_of_messages = [] of String
      handler = Server::Handler.new("/bounded-protocol-spec") do |socket, _context|
        socket.on_message { |message| list_of_messages << message }
      end
      request = HTTP::Request.new("GET", "/bounded-protocol-spec", HTTP::Headers{
        "Upgrade"               => "websocket",
        "Connection"            => "Upgrade",
        "Sec-WebSocket-Version" => HTTP::WebSocket::Protocol::VERSION,
        "Sec-WebSocket-Key"     => "dGhlIHNhbXBsZSBub25jZQ==",
      })
      context = HTTP::Server::Context.new(request, HTTP::Server::Response.new(IO::Memory.new))
      handler.call(context)
      context.response.status.should eq HTTP::Status::SWITCHING_PROTOCOLS

      limit = Amber.settings.params.max_websocket_message_bytes
      reply = IO::Memory.new
      upgrade = context.response.upgrade_handler || raise "the handler did not upgrade"
      upgrade.call(IO::Stapled.new(IO::Memory.new(client_frames("x" * (limit + 1), 65_536)), reply))

      list_of_messages.should be_empty
      close_code(reply.to_slice).should eq 1009
    end
  end
end
