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
  end
end