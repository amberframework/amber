require "../../spec_helper"

module Amber
  describe "ClientSocket decoder integration" do
    Spec.after_each do
      Amber::WebSockets::Channel.reset_presence
    end

    describe "default decoder" do
      it "uses JsonDecoder by default" do
        decoder = UserSocket.decoder
        decoder.should be_a(WebSockets::Decoders::JsonDecoder)
      end

      it "decodes JSON messages through the socket" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        client_socket.on_message({event: "join", topic: "user_room:123"}.to_json)
        client_socket.subscribed_to_topic?("user_room:123").should be_true

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end

    describe "custom decoder" do
      it "uses TextDecoder when configured" do
        decoder = TextDecoderSocket.decoder
        decoder.should be_a(WebSockets::Decoders::TextDecoder)
      end
    end

    describe "error handling in decode" do
      it "should invoke on_error when decoding fails" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        # Send invalid JSON - should trigger on_error, not crash
        client_socket.on_message("this is not valid json {{{}}")

        client_socket.list_of_errors.size.should be > 0

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end

      it "should not crash the socket on decode errors" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        # Send invalid message - should not raise
        client_socket.on_message("broken")

        # Socket should still be functional
        client_socket.socket.closed?.should be_false

        # Should still accept valid messages
        client_socket.on_message({event: "join", topic: "user_room:456"}.to_json)
        client_socket.subscribed_to_topic?("user_room:456").should be_true

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end
  end
end
