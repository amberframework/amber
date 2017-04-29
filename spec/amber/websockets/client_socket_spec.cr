require "../../../spec_helper"

module Amber
  describe WebSockets::ClientSocket do
    describe "#channel" do
      it "should add channels" do
        UserSocket.channels.should eq [{path: "user_room/*", channel: UserChannel}]
      end
    end

    describe "#initialize" do
      it "should set the socket and socket id" do
        ws, client_socket = create_user_socket

        client_socket.socket.should eq ws
        client_socket.id.should eq ws.object_id
      end
    end

    describe "#on_connect" do 
      it "should default to true" do
        ws, client_socket = create_user_socket
        client_socket.on_connect.should eq true
      end
    end

    describe "#authorized?" do
      it "should equal on_connect" do
        ws, client_socket = create_user_socket
        client_socket.authorized?.should eq client_socket.on_connect
      end
    end
  end
end