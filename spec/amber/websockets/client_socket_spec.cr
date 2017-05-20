require "../../../spec_helper"

module Amber
  describe WebSockets::ClientSocket do
    describe "#channel" do
      it "should add channels" do
        UserSocket.channels[0][:path].should eq "user_room:*"
        UserSocket.channels[0][:channel].should be_a UserChannel
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
        client_socket.on_connect.should be_true
      end
    end

    describe "#authorized?" do
      it "should equal on_connect" do
        ws, client_socket = create_user_socket
        client_socket.authorized?.should eq client_socket.on_connect
      end
    end

    describe "#on_message" do
      describe "join event" do
        it "should add a subscription" do
          ws, client_socket = create_user_socket
          client_socket.subscribed_to_topic?("user_room:123").should be_false
          client_socket.on_message({event: "join", topic: "user_room:123"}.to_json)
          client_socket.subscribed_to_topic?("user_room:123").should be_true
        end
      end

      describe "leave event" do
        it "should remove the subscription" do
          ws, client_socket = create_user_socket
          client_socket.on_message({event: "join", topic: "user_room:123"}.to_json)
          client_socket.subscribed_to_topic?("user_room:123").should be_true
          client_socket.on_message({event: "leave", topic: "user_room:123"}.to_json)
          client_socket.subscribed_to_topic?("user_room:123").should be_false
        end
      end
    end
  end
end
