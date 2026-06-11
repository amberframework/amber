require "./pubsub_adapter"
require "json"

module Amber::Adapters
  # In-memory implementation of PubSubAdapter.
  #
  # This adapter provides pub/sub messaging using in-memory channels and fiber-based
  # message routing. This is the default pub/sub adapter and is suitable for
  # development, testing, and single-instance applications.
  #
  # **Note**: Messages are only routed within the same application instance.
  # For production applications that require multi-instance deployments or
  # distributed messaging, consider using a Redis-based or message queue adapter.
  #
  # ## Usage
  #
  # ```
  # # Configure in your application settings
  # config.pubsub_adapter = Amber::Adapters::MemoryPubSubAdapter.new
  # ```
  class MemoryPubSubAdapter < PubSubAdapter
    # Internal structure to store topic subscriptions
    private record Subscription, topic : String, listener : (String, JSON::Any) -> Nil

    # Thread-safe subscription storage
    @subscriptions : Hash(String, Array(Subscription))
    @mutex : Mutex

    def initialize
      @subscriptions = Hash(String, Array(Subscription)).new
      @mutex = Mutex.new
    end

    # Publishes a message to the specified topic.
    #
    # The message is immediately delivered to all subscribers of the topic
    # in the current application instance.
    #
    # @param topic The topic to publish to
    # @param sender_id Unique identifier of the message sender
    # @param message The message payload as JSON::Any
    def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
      subscribers = get_subscribers(topic)
      return if subscribers.empty?

      # Deliver message to all subscribers asynchronously
      spawn do
        subscribers.each do |subscription|
          begin
            subscription.listener.call(sender_id, message)
          rescue ex
            # Log the error but don't stop other deliveries
            # TODO: Add proper logging when Amber's logging system is available
            STDERR.puts "Error delivering message to subscriber: #{ex.message}"
          end
        end
      end
    end

    # Subscribes to messages on the specified topic.
    #
    # The listener will be called for each message published to the topic.
    # Multiple listeners can subscribe to the same topic.
    #
    # @param topic The topic to subscribe to
    # @param block Callback block that receives sender_id and message
    def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
      @mutex.synchronize do
        @subscriptions[topic] ||= Array(Subscription).new
        @subscriptions[topic] << Subscription.new(topic, block)
      end
    end

    # Unsubscribes from a topic.
    #
    # This removes all listeners for the specified topic. If you need to remove
    # specific listeners, you'll need to track them separately.
    #
    # @param topic The topic to unsubscribe from
    def unsubscribe(topic : String) : Nil
      @mutex.synchronize do
        @subscriptions.delete(topic)
      end
    end

    # Lists all active topics that have subscribers.
    #
    # @return Array of topic names that currently have active subscriptions
    def active_topics : Array(String)
      @mutex.synchronize do
        @subscriptions.keys.select { |topic| !@subscriptions[topic].empty? }
      end
    end

    # Returns the number of subscribers for a given topic.
    #
    # @param topic The topic to check
    # @return Number of active subscribers for the topic
    def subscriber_count(topic : String) : Int32
      @mutex.synchronize do
        @subscriptions[topic]?.try(&.size) || 0
      end
    end

    # Checks if there are any subscribers for the given topic.
    #
    # @param topic The topic to check
    # @return True if there are subscribers, false otherwise
    def has_subscribers?(topic : String) : Bool
      subscriber_count(topic) > 0
    end

    # Unsubscribes from all topics and cleans up any resources.
    def unsubscribe_all : Nil
      @mutex.synchronize do
        @subscriptions.clear
      end
    end

    # Closes the adapter and cleans up any resources.
    def close : Nil
      unsubscribe_all
    end

    # Clears all subscriptions.
    #
    # This is mainly useful for testing or when shutting down the adapter.
    def clear_all_subscriptions : Nil
      unsubscribe_all
    end

    # Returns statistics about the current state of the adapter.
    #
    # @return Hash containing metrics like total topics, total subscribers, etc.
    def stats : Hash(String, Int32)
      @mutex.synchronize do
        total_subscribers = @subscriptions.values.sum(&.size)
        active_topics = @subscriptions.count { |_, subs| !subs.empty? }

        {
          "total_topics"      => @subscriptions.size,
          "active_topics"     => active_topics,
          "total_subscribers" => total_subscribers,
        }
      end
    end

    # Gets a copy of current subscribers for a topic (thread-safe)
    private def get_subscribers(topic : String) : Array(Subscription)
      @mutex.synchronize do
        @subscriptions[topic]?.try(&.dup) || Array(Subscription).new
      end
    end
  end
end
