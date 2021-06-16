

require "../../../spec_helper"

module Amber
  describe Amber::WebSockets::Adapters::RedisAdapter do

    describe "#initialize" do
      it "should subscribe to CHANNEL_TOPIC_PATHS" do
        
        
        _, client_socket = create_user_socket
        _, client_socket2 = create_user_socket

        
        
        channel = UserSocket.channels[0][:channel]
        channel2 = UserSocket.channels[1][:channel]
        
        channel.subscribe_to_channel(client_socket, "{}")
        channel.subscribe_to_channel(client_socket2, "{}")
        
        channel2.subscribe_to_channel(client_socket2, "{}")
        channel2.subscribe_to_channel(client_socket, "{}")
        
        # channel.test_field.last.should eq "handle joined #{client_socket.id}"
        # Amber::WebSockets::CHANNEL_TOPIC_PATHS.should eq ["user_room", "secondary_room"]
        
        Amber::Server.pubsub_adapter = Amber::WebSockets::Adapters::RedisAdapter

        redis_adapter = Amber::Server.instance.pubsub_adapter.instance

        sleep 1.second

        redis_adapter.as(Amber::WebSockets::Adapters::RedisAdapter).subscribed.should eq true
      end
    end

    describe "#publish" do
      it "should publish the message to the channel" do
        _, client_socket = create_user_socket
        _, client_socket2 = create_user_socket

        Amber::Server.instance.pubsub_adapter = Amber::WebSockets::Adapters::RedisAdapter
        
        channel = UserSocket.channels[0][:channel]
        channel2 = UserSocket.channels[1][:channel]
        
        channel.subscribe_to_channel(client_socket, "{}")
        channel.subscribe_to_channel(client_socket2, "{}")
        
        channel2.subscribe_to_channel(client_socket2, "{}")
        channel2.subscribe_to_channel(client_socket, "{}")
        
        # channel.test_field.last.should eq "handle joined #{client_socket.id}"
        Amber::WebSockets::CHANNEL_TOPIC_PATHS.should eq ["user_room", "secondary_room"]
        
        redis_adapter = Amber::WebSockets::Adapters::RedisAdapter.new

        sleep 1.second

        redis_adapter.subscribed.should eq true

        channel = UserSocket.channels[0][:channel]
        message = JSON.parse({"event" => "message", "topic" => "user_room:123", "subject" => "msg:new", "payload" => {"message" => "hey guys"}}.to_json)
        channel.on_message("123", message)
        channel.test_field.last.should eq "hey guys"
      end
    end


  end
end
