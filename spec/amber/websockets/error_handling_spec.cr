require "../../spec_helper"

module Amber
  describe "WebSocket error handling" do
    Spec.after_each do
      Amber::WebSockets::Channel.reset_presence
    end

    describe "socket-level error handling" do
      it "should invoke on_error on the socket when decoding fails" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        client_socket.on_message("not json")
        client_socket.list_of_errors.size.should be > 0
        client_socket.list_of_errors.first.should be_a(Amber::WebSockets::Decoders::DecoderError)

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end

      it "should invoke handle_error with context information" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        client_socket.on_message("bad data")
        client_socket.list_of_errors.size.should be > 0

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end

    describe "channel-level error handling" do
      it "should call on_error when handle_joined raises" do
        error_channel = ErrorChannel.new("error_room")
        _, client_socket = create_user_socket

        # Should not propagate the error
        error_channel.subscribe_to_channel(client_socket, "{}")

        error_channel.list_of_errors.size.should eq 1
        error_channel.list_of_errors.first.message.should eq "join error"
      end

      it "should not crash the socket when a channel errors" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        # The socket should remain functional even after channel errors
        client_socket.socket.closed?.should be_false

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end

    describe "error isolation between channels" do
      it "errors in one channel should not affect another channel's subscriptions" do
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        # Join a working channel
        client_socket.on_message({event: "join", topic: "user_room:123"}.to_json)
        client_socket.subscribed_to_topic?("user_room:123").should be_true

        # The socket is still working after encountering an error
        client_socket.socket.closed?.should be_false
        client_socket.subscribed_to_topic?("user_room:123").should be_true

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end
  end
end
