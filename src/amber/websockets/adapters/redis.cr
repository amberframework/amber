module Amber::WebSockets::Adapters
  # Allows websocket connections through redis pub/sub.
  class RedisAdapter
    @subscriber : Redis
    @publisher : Redis
    @subscribed : Bool = false
    @listeners : Hash(String,Proc(String, JSON::Any, Nil)) = Hash(String, Proc(String, JSON::Any, Nil)).new

    def self.instance
      @@instance ||= new
    end

    def subscribed # test helper
      @subscribed
    end

    # Establish subscribe and publish connections to Redis
    def initialize
      @subscriber = Redis.new(url: Amber.settings.redis_url)
      @publisher = Redis.new(url: Amber.settings.redis_url)

      spawn do
        @subscriber.subscribe(CHANNEL_TOPIC_PATHS) do |on|
          on.message do |_, m|
            Fiber.yield
            msg = JSON.parse(m)
            sender_id = msg["sender"].as_s
            message = msg["msg"]
            channel_name = message["topic"].to_s.split(":").first
            @listeners[channel_name].call(sender_id, message)
          end
          on.subscribe do |channel, subscriptions|
            Fiber.yield
            Log.info { "Subscribed to Redis channel #{channel}" }
            @subscribed = true
          end
          on.unsubscribe do |channel, subscriptions|
            Fiber.yield
            Log.info { "Unsubscribed from Redis channel #{channel}" }
            @subscribed = false
          end
        end
      end
    end

    # Publish the *message* to the redis publisher with topic *topic_path*
    def publish(topic_path, client_socket, message)
      @publisher.publish(topic_path, {sender: client_socket.id, msg: message}.to_json)
    end

    # Add a redis subscriber with topic *topic_path*
    def on_message(topic_path, listener)
      Log.info { "Setting  websocket adapter listener for #{topic_path}"}
      @listeners[topic_path] = listener
      begin
        @subscriber.subscribe(topic_path)
      rescue # if we can't do it we're not in a subscribe loop, just resubscribe to all channels
        spawn do
          @subscriber.subscribe(CHANNEL_TOPIC_PATHS) do |on|
            on.message do |_, m|
              Fiber.yield
              msg = JSON.parse(m)
              sender_id = msg["sender"].as_s
              message = msg["msg"]
              channel_name = message["topic"].to_s.split(":").first
              @listeners[channel_name].call(sender_id, message)
            end
            on.subscribe do |channel, subscriptions|
              Fiber.yield
              Log.info { "Subscribed to Redis channel #{channel}" }
              @subscribed = true
            end
            on.unsubscribe do |channel, subscriptions|
              Fiber.yield
              Log.info { "Unsubscribed from Redis channel #{channel}" }
              @subscribed = false # just in case we do get unsubscribed some how
            end
          end
        end
      end
    end
  end
end