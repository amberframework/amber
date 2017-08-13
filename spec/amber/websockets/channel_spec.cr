require "../../../spec_helper"

module Amber
  describe WebSockets::ClientSocket do
    describe "#on_message" do
      it "should call `handle_message`" do
        channel = UserSocket.channels[0][:channel]
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        channel.on_message("123", message)
        channel.test_field.last.should eq "hey guys"
      end
    end

    describe "#subscribe_to_channel" do
      it "should call `handle_joined`" do
        ws, client_socket = create_user_socket
        channel = UserSocket.channels[0][:channel]
        channel.subscribe_to_channel(client_socket, "{}")
        channel.test_field.last.should eq "handle joined #{client_socket.id}"
      end
    end

    describe "#unsubscribe_from_channel" do
      it "should call `handle_leave`" do
        ws, client_socket = create_user_socket
        channel = UserSocket.channels[0][:channel]
        channel.unsubscribe_from_channel(client_socket)
        channel.test_field.last.should eq "handle leave #{client_socket.id}"
      end
    end
  end
end
