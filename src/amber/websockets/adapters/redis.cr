module Amber::WebSockets::Adapters
  # Allows websocket connections through redis pub/sub.
  class RedisAdapter
    @subscriber : Redis
    @publisher : Redis

    def self.instance
      @@instance ||= new
    end

    # Establish subscribe and publish connections to Redis
    def initialize
      @subscriber = Redis.new(url: Amber::Server.redis_url)
      @publisher = Redis.new(url: Amber::Server.redis_url)
    end

    # Publish the *message* to the redis publisher with topic *topic_path*
    def publish(topic_path, client_socket, message)
      @publisher.publish(topic_path, {sender: client_socket.id, msg: message}.to_json)
    end

    # Add a redis subscriber with topic *topic_path*
    def on_message(topic_path, listener)
      spawn do
        @subscriber.subscribe(topic_path) do |on|
          on.message do |channel, m|
            msg = JSON.parse(m)
            sender_id = msg["sender"].as_s
            message = msg["msg"]
            listener.call(sender_id, message)
          end
        end
      end
    end
  end
end
