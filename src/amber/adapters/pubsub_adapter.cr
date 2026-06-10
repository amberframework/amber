module Amber::Adapters
  # Abstract base class for pub/sub messaging adapters used by WebSocket channels.
  #
  # All pub/sub implementations should inherit from this class and implement
  # the required abstract methods. This allows the Amber framework to work with
  # any messaging backend (Redis, in-memory, database, message queues, etc.)
  # through a unified interface.
  #
  # Example implementation:
  #
  # ```
  # class CustomPubSubAdapter < Amber::Adapters::PubSubAdapter
  #   def initialize(@message_broker : MyMessageBroker)
  #   end
  #
  #   def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
  #     @message_broker.send_message(topic, {sender: sender_id, msg: message}.to_json)
  #   end
  #
  #   # ... implement other abstract methods
  # end
  # ```
  abstract class PubSubAdapter
    # Core pub/sub operations

    # Publishes a message to all subscribers of the specified topic.
    #
    # - `topic`: The topic/channel to publish to
    # - `sender_id`: Unique identifier of the message sender (usually client socket ID)
    # - `message`: The message content to publish
    abstract def publish(topic : String, sender_id : String, message : JSON::Any) : Nil

    # Subscribes to messages on the specified topic.
    # The provided block will be called for each received message.
    #
    # - `topic`: The topic/channel to subscribe to
    # - `block`: Callback that receives (sender_id, message) for each published message
    #
    # Note: The sender_id allows subscribers to filter out their own messages if needed.
    abstract def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil

    # Unsubscribes from the specified topic.
    # After calling this, the subscriber should no longer receive messages for this topic.
    #
    # - `topic`: The topic/channel to unsubscribe from
    abstract def unsubscribe(topic : String) : Nil

    # Unsubscribes from all topics and cleans up any resources.
    # This should be called when shutting down the adapter.
    abstract def unsubscribe_all : Nil

    # Lifecycle and health operations

    # Closes the adapter and cleans up any resources (connections, background processes, etc.)
    # Should be called when the application is shutting down.
    abstract def close : Nil

    # Optional methods with default implementations

    # Returns true if the adapter is healthy and ready to handle pub/sub operations.
    # Override this method to implement health checks for your messaging backend.
    def healthy? : Bool
      true
    end

    # Returns the number of active subscribers across all topics.
    # This is useful for monitoring and debugging. Override if your backend can provide this efficiently.
    def subscriber_count : Int32
      0
    end

    # Returns a list of all active topics that have subscribers.
    # This is useful for monitoring and debugging. Override if your backend can provide this efficiently.
    def active_topics : Array(String)
      Array(String).new
    end

    # Called when a topic becomes active (gets its first subscriber).
    # Override this to perform topic-specific setup operations.
    protected def on_topic_activated(topic : String) : Nil
      # Default implementation does nothing
    end

    # Called when a topic becomes inactive (loses its last subscriber).
    # Override this to perform topic-specific cleanup operations.
    protected def on_topic_deactivated(topic : String) : Nil
      # Default implementation does nothing
    end
  end
end
