require "../../spec_helper"

module Amber
  describe WebSockets::Channel do
    describe "#on_message" do
      it "should call `handle_message`" do
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        _, client_socket = create_user_socket
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)

        channel = client_socket.get_channel("user_room").not_nil!
        channel.handle_message(client_socket, message)

        channel.as(UserChannel).test_field.last.should eq "hey guys"

        Amber::WebSockets::ClientSockets.remove_client_socket(client_socket)
      end
    end

    describe "#subscribe_to_channel" do
      it "should call `handle_joined`" do
        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!
        channel.subscribe_to_channel(client_socket, "{}")
        channel.as(UserChannel).test_field.should contain("handle joined #{client_socket.id}")
      end

      it "should call `after_join` after `handle_joined`" do
        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!
        channel.subscribe_to_channel(client_socket, "{}")

        test_field = channel.as(UserChannel).test_field
        test_field.should contain("handle joined #{client_socket.id}")
        test_field.should contain("after join #{client_socket.id}")

        # Verify ordering: handle_joined comes before after_join
        joined_index = test_field.index("handle joined #{client_socket.id}").not_nil!
        after_index = test_field.index("after join #{client_socket.id}").not_nil!
        joined_index.should be < after_index
      end
    end

    describe "#unsubscribe_from_channel" do
      it "should call `handle_leave`" do
        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!
        channel.unsubscribe_from_channel(client_socket)
        channel.as(UserChannel).test_field.should contain("handle leave #{client_socket.id}")
      end

      it "should call `after_leave` after `handle_leave`" do
        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!
        channel.unsubscribe_from_channel(client_socket)

        test_field = channel.as(UserChannel).test_field
        test_field.should contain("handle leave #{client_socket.id}")
        test_field.should contain("after leave #{client_socket.id}")

        # Verify ordering: handle_leave comes before after_leave
        leave_index = test_field.index("handle leave #{client_socket.id}").not_nil!
        after_index = test_field.index("after leave #{client_socket.id}").not_nil!
        leave_index.should be < after_index
      end
    end

    describe "#handle_message" do
      it "should process the message" do
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!

        channel.handle_message(client_socket, message)

        channel.as(UserChannel).test_field.last.should eq "hey guys"
      end
    end

    describe "#on_error" do
      it "should catch errors during subscribe_to_channel" do
        error_channel = ErrorChannel.new("error_room")
        _, client_socket = create_user_socket

        # This should not raise because on_error catches it
        error_channel.subscribe_to_channel(client_socket, "{}")

        error_channel.list_of_errors.size.should eq 1
        error_channel.list_of_errors.first.message.should eq "join error"
      end
    end

    describe ".broadcast_to" do
      it "should broadcast to all subscribers of the topic" do
        chan = Channel(String).new
        http_server, ws = create_socket_server
        client_socket = Amber::WebSockets::ClientSockets.client_sockets.values.first
        Amber::WebSockets::ClientSockets.add_client_socket(client_socket)
        client_socket.on_message({event: "join", topic: "user_room:939"}.to_json)
        ws.on_message &->(msg : String) { chan.send(msg) }

        UserChannel.broadcast_to("user_room:939", "msg:new", {"message" => "server announcement"})

        msg = JSON.parse(chan.receive)
        msg["event"]?.should eq "msg:new"
        msg["topic"]?.should eq "user_room:939"
        msg["payload"]["message"]?.should eq "server announcement"

        client_socket.disconnect!
        http_server.close
      end
    end

    describe "presence tracking" do
      it "should track presence when a socket subscribes" do
        Amber::WebSockets::Channel.reset_presence

        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!
        channel.subscribe_to_channel(client_socket, "{}")

        presence = channel.presence_list
        presence.has_key?(client_socket.id).should be_true
        presence[client_socket.id]["socket_id"].should eq client_socket.id
        presence[client_socket.id].has_key?("joined_at").should be_true
      end

      it "should remove presence when a socket unsubscribes" do
        Amber::WebSockets::Channel.reset_presence

        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!

        channel.subscribe_to_channel(client_socket, "{}")
        channel.presence_list.has_key?(client_socket.id).should be_true

        channel.unsubscribe_from_channel(client_socket)
        channel.presence_list.has_key?(client_socket.id).should be_false
      end

      it "should return the count of present sockets" do
        Amber::WebSockets::Channel.reset_presence

        _, client_socket1 = create_user_socket
        _, client_socket2 = create_user_socket

        channel1 = client_socket1.get_channel("user_room").not_nil!
        channel2 = client_socket2.get_channel("user_room").not_nil!

        channel1.subscribe_to_channel(client_socket1, "{}")
        channel2.subscribe_to_channel(client_socket2, "{}")

        channel1.presence_count.should eq 2

        Amber::WebSockets::Channel.reset_presence
      end

      it "should be accessible at the class level" do
        Amber::WebSockets::Channel.reset_presence

        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!

        channel.subscribe_to_channel(client_socket, "{}")

        class_presence = UserChannel.presence_list("user_room")
        class_presence.has_key?(client_socket.id).should be_true

        Amber::WebSockets::Channel.reset_presence
      end

      it "should reset presence data" do
        Amber::WebSockets::Channel.reset_presence

        _, client_socket = create_user_socket
        channel = client_socket.get_channel("user_room").not_nil!

        channel.subscribe_to_channel(client_socket, "{}")
        channel.presence_count.should be > 0

        Amber::WebSockets::Channel.reset_presence
        channel.presence_count.should eq 0
      end
    end
  end
end
