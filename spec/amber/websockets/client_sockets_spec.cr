require "../../../spec_helper"

module Amber
  describe WebSockets::ClientSockets do
    describe "#add_client_socket" do
      it "should add the client socket to the list" do
        ws, client_socket = create_user_socket
        WebSockets::ClientSockets.add_client_socket(client_socket)

        WebSockets::ClientSockets.client_sockets[client_socket.id].should eq client_socket
      end
    end

    describe "#remove_client_socket do" do
      it "should remove the client socket from the list" do
        ws, client_socket = create_user_socket
        WebSockets::ClientSockets.add_client_socket(client_socket)
        WebSockets::ClientSockets.remove_client_socket(client_socket)

        WebSockets::ClientSockets.client_sockets[client_socket.id]?.should be_nil
      end
    end

    describe "#get_subscribers_for_topic" do
      it "should return all of the subscribers for the topic" do
        ws, client_socket1 = create_user_socket
        ws, client_socket2 = create_user_socket
        WebSockets::ClientSockets.add_client_socket(client_socket1)
        WebSockets::ClientSockets.add_client_socket(client_socket2)
        client_socket1.on_message({event: "join", topic: "user_room:123"}.to_json)
        client_socket2.on_message({event: "join", topic: "user_room:123"}.to_json)
        WebSockets::ClientSockets.get_subscribers_for_topic("user_room:123").values.should eq [client_socket1, client_socket2]
      end
    end
  end
end
