require "http"
require "json"

module Amber::Testing
  # Provides helpers for testing WebSocket channels.
  #
  # ```
  # describe "ChatChannel" do
  #   include Amber::Testing::WebSocketHelpers
  #
  #   it "handles messages" do
  #     test_socket = create_test_socket("/chat")
  #     test_socket.send({"event" => "join", "topic" => "chat:lobby"}.to_json)
  #     test_socket.close
  #   end
  # end
  # ```
  module WebSocketHelpers
    # Create a test WebSocket connection to the given path.
    # This starts a minimal HTTP server on an unused port, connects
    # a WebSocket client, and returns a TestWebSocket for interaction.
    def create_test_socket(path : String) : TestWebSocket
      TestWebSocket.new(path)
    end
  end

  # Wraps a WebSocket connection for use in tests.
  # Tracks sent and received messages and provides a simple
  # interface for interacting with WebSocket channels.
  class TestWebSocket
    # Messages received from the server.
    getter list_of_received_messages : Array(String) = [] of String

    # Messages sent by the test.
    getter list_of_sent_messages : Array(String) = [] of String

    getter? is_closed : Bool = false

    @server : HTTP::Server?
    @client_socket : HTTP::WebSocket?
    @port : Int32 = 0

    def initialize(@path : String)
      start_server
      connect_client
    end

    # Send a message string through the WebSocket.
    def send(message : String)
      raise "Cannot send on a closed socket" if is_closed?
      @list_of_sent_messages << message
      @client_socket.try &.send(message)
      # Allow the server fiber to process the message
      sleep 50.milliseconds
    end

    # Send a JSON-structured message through the WebSocket.
    def send_json(event : String, topic : String, payload = {} of String => String)
      message = {
        "event"   => event,
        "topic"   => topic,
        "payload" => payload,
      }.to_json
      send(message)
    end

    # Return the most recently received message, or nil if none.
    def receive : String?
      list_of_received_messages.last?
    end

    # Close the WebSocket connection and shut down the test server.
    def close
      return if is_closed?
      @is_closed = true
      @client_socket.try do |socket|
        socket.close unless socket.closed?
      end
      @server.try &.close
    end

    private def start_server
      ready_channel = ::Channel(Int32).new

      spawn do
        handler = Amber::WebSockets::Server.create_endpoint(@path, TestClientSocket)
        server = HTTP::Server.new(handler)
        @server = server
        address = server.bind_unused_port
        ready_channel.send(address.port)
        server.listen
      end

      @port = ready_channel.receive
    end

    private def connect_client
      ws = HTTP::WebSocket.new("ws://127.0.0.1:#{@port}")
      @client_socket = ws

      ws.on_message do |message|
        @list_of_received_messages << message
      end

      spawn { ws.run }
      # Allow the connection to establish
      sleep 50.milliseconds
    end
  end

  # A minimal client socket used internally by TestWebSocket.
  # Users testing their own socket types should use WebSocketHelpers
  # with their actual socket structs.
  struct TestClientSocket < Amber::WebSockets::ClientSocket
    def on_connect : Bool
      true
    end
  end
end
