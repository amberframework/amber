require "../../spec_helper"

module Amber
  describe "WebSocket connection recovery" do
    Spec.after_each do
      Amber::WebSockets::ClientSockets.clear_disconnected_connections
    end

    describe "connection_id" do
      it "assigns a unique connection_id on creation" do
        _, client_socket = create_user_socket
        client_socket.connection_id.should_not be_nil
        client_socket.connection_id.size.should eq 36 # UUID format
      end

      it "preserves connection_id when creating with an explicit id" do
        _, client_socket = create_user_socket_with_connection_id("custom-connection-id")
        client_socket.connection_id.should eq "custom-connection-id"
      end

      it "assigns different socket ids even with the same connection_id" do
        _, socket1 = create_user_socket_with_connection_id("shared-id")
        _, socket2 = create_user_socket_with_connection_id("shared-id")
        socket1.id.should_not eq socket2.id
        socket1.connection_id.should eq socket2.connection_id
      end
    end

    describe "disconnection tracking" do
      it "tracks a disconnected connection" do
        _, client_socket = create_user_socket
        connection_id = client_socket.connection_id

        Amber::WebSockets::ClientSockets.track_disconnection(client_socket)
        Amber::WebSockets::ClientSockets.has_disconnected_connection?(connection_id).should be_true
      end

      it "recovers a disconnected connection within the window" do
        _, client_socket = create_user_socket
        connection_id = client_socket.connection_id

        Amber::WebSockets::ClientSockets.track_disconnection(client_socket)

        recovered = Amber::WebSockets::ClientSockets.recover_connection(connection_id)
        recovered.should_not be_nil
        recovered.not_nil!.connection_id.should eq connection_id
      end

      it "returns nil when recovering a non-existent connection" do
        recovered = Amber::WebSockets::ClientSockets.recover_connection("non-existent-id")
        recovered.should be_nil
      end

      it "removes the connection from tracking after recovery" do
        _, client_socket = create_user_socket
        connection_id = client_socket.connection_id

        Amber::WebSockets::ClientSockets.track_disconnection(client_socket)
        Amber::WebSockets::ClientSockets.recover_connection(connection_id)

        # Should no longer be tracked
        Amber::WebSockets::ClientSockets.has_disconnected_connection?(connection_id).should be_false
      end
    end

    describe "message buffering" do
      it "buffers messages for a disconnected connection" do
        _, client_socket = create_user_socket
        connection_id = client_socket.connection_id

        Amber::WebSockets::ClientSockets.track_disconnection(client_socket)
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "message 1")
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "message 2")

        recovered = Amber::WebSockets::ClientSockets.recover_connection(connection_id)
        recovered.should_not be_nil
        recovered.not_nil!.list_of_buffered_messages.should eq ["message 1", "message 2"]
      end

      it "drops oldest messages when buffer is full" do
        _, client_socket = create_user_socket
        connection_id = client_socket.connection_id

        # Set a small buffer size for testing
        original_size = Amber::WebSockets::ClientSocket::DEFAULT_MESSAGE_BUFFER_SIZE
        Amber::WebSockets::ClientSockets.max_message_buffer_size = 3

        Amber::WebSockets::ClientSockets.track_disconnection(client_socket)
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "msg 1")
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "msg 2")
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "msg 3")
        Amber::WebSockets::ClientSockets.buffer_message(connection_id, "msg 4")

        recovered = Amber::WebSockets::ClientSockets.recover_connection(connection_id)
        recovered.should_not be_nil
        recovered.not_nil!.list_of_buffered_messages.should eq ["msg 2", "msg 3", "msg 4"]

        # Restore default
        Amber::WebSockets::ClientSockets.max_message_buffer_size = original_size
      end

      it "ignores buffer requests for unknown connection ids" do
        # Should not raise
        Amber::WebSockets::ClientSockets.buffer_message("unknown-id", "message")
      end
    end

    describe "on_reconnect callback" do
      it "should be available on the socket" do
        _, client_socket = create_user_socket
        client_socket.responds_to?(:on_reconnect).should be_true
      end
    end

    describe "clear_disconnected_connections" do
      it "removes all tracked disconnected connections" do
        _, socket1 = create_user_socket
        _, socket2 = create_user_socket

        Amber::WebSockets::ClientSockets.track_disconnection(socket1)
        Amber::WebSockets::ClientSockets.track_disconnection(socket2)

        Amber::WebSockets::ClientSockets.has_disconnected_connection?(socket1.connection_id).should be_true
        Amber::WebSockets::ClientSockets.has_disconnected_connection?(socket2.connection_id).should be_true

        Amber::WebSockets::ClientSockets.clear_disconnected_connections

        Amber::WebSockets::ClientSockets.has_disconnected_connection?(socket1.connection_id).should be_false
        Amber::WebSockets::ClientSockets.has_disconnected_connection?(socket2.connection_id).should be_false
      end
    end
  end
end
