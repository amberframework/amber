require "../../spec_helper"
require "../../../src/amber/testing"

module WebSocketHelpersSpec
  extend Amber::Testing::WebSocketHelpers

  describe Amber::Testing::TestWebSocket do
    describe "#send" do
      it "tracks sent messages" do
        test_socket = Amber::Testing::TestWebSocket.new("/ws_test_send")
        test_socket.send("hello")
        test_socket.list_of_sent_messages.size.should eq(1)
        test_socket.list_of_sent_messages.first.should eq("hello")
        test_socket.close
      end
    end

    describe "#send_json" do
      it "sends a JSON formatted message" do
        test_socket = Amber::Testing::TestWebSocket.new("/ws_test_json")
        test_socket.send_json("join", "room:lobby", {"user" => "Alice"})
        test_socket.list_of_sent_messages.size.should eq(1)
        message = JSON.parse(test_socket.list_of_sent_messages.first)
        message["event"].as_s.should eq("join")
        message["topic"].as_s.should eq("room:lobby")
        test_socket.close
      end
    end

    describe "#close" do
      it "marks the socket as closed" do
        test_socket = Amber::Testing::TestWebSocket.new("/ws_test_close")
        test_socket.is_closed?.should be_false
        test_socket.close
        test_socket.is_closed?.should be_true
      end

      it "prevents sending after close" do
        test_socket = Amber::Testing::TestWebSocket.new("/ws_test_no_send")
        test_socket.close
        expect_raises(Exception, "Cannot send on a closed socket") do
          test_socket.send("should fail")
        end
      end
    end

    describe "#receive" do
      it "returns nil when no messages received" do
        test_socket = Amber::Testing::TestWebSocket.new("/ws_test_no_recv")
        test_socket.receive.should be_nil
        test_socket.close
      end
    end
  end

  describe Amber::Testing::WebSocketHelpers do
    describe "#create_test_socket" do
      it "creates a test socket connected to the given path" do
        test_socket = WebSocketHelpersSpec.create_test_socket("/ws_test_helper")
        test_socket.should be_a(Amber::Testing::TestWebSocket)
        test_socket.is_closed?.should be_false
        test_socket.close
      end
    end
  end
end
