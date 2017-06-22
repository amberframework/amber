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
      @subscriber = Redis.new(url: Amber::Server.instance.redis_url)
      @publisher = Redis.new(url: Amber::Server.instance.redis_url)
    end

    # Publish the *message* to the redis publisher with topic *topic_path*
    def publish(topic_path, message)
      @publisher.publish(topic_path, message.to_json)
    end

    # Add a redis subscriber with topic *topic_path*
    def on_message(topic_path, listener)
      spawn do
        @subscriber.subscribe(topic_path) do |on|
          on.message do |channel, message|
            listener.call(JSON.parse(message))
          end
        end
      end
    end
  end
end
