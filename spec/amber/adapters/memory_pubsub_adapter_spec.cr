require "../../spec_helper"
require "json"

describe Amber::Adapters::MemoryPubSubAdapter do
  describe "#publish and #subscribe" do
    it "delivers messages to subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")
      received_messages = [] of {String, JSON::Any}

      # Subscribe to the topic
      adapter.subscribe(topic) do |sid, msg|
        received_messages << {sid, msg}
      end

      # Publish a message
      adapter.publish(topic, sender_id, message)

      # Give some time for message delivery
      sleep(0.1.seconds)

      received_messages.size.should eq(1)
      received_messages[0][0].should eq(sender_id)
      received_messages[0][1].should eq(message)
    end

    it "delivers messages to multiple subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")
      received_messages_1 = [] of {String, JSON::Any}
      received_messages_2 = [] of {String, JSON::Any}

      # Multiple subscribers
      adapter.subscribe(topic) do |sid, msg|
        received_messages_1 << {sid, msg}
      end

      adapter.subscribe(topic) do |sid, msg|
        received_messages_2 << {sid, msg}
      end

      # Publish a message
      adapter.publish(topic, sender_id, message)

      # Give some time for message delivery
      sleep(0.1.seconds)

      # Both subscribers should receive the message
      received_messages_1.size.should eq(1)
      received_messages_2.size.should eq(1)
    end

    it "handles publishing to topics with no subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")

      # Should not raise an error
      adapter.publish("empty_topic", sender_id, message)
    end

    it "isolates messages between different topics" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")
      topic1_messages = [] of {String, JSON::Any}
      topic2_messages = [] of {String, JSON::Any}

      # Subscribe to different topics
      adapter.subscribe("topic1") do |sid, msg|
        topic1_messages << {sid, msg}
      end

      adapter.subscribe("topic2") do |sid, msg|
        topic2_messages << {sid, msg}
      end

      # Publish to topic1 only
      adapter.publish("topic1", sender_id, message)

      sleep(0.1.seconds)

      topic1_messages.size.should eq(1)
      topic2_messages.size.should eq(0)
    end
  end

  describe "#unsubscribe" do
    it "removes all subscribers from a topic" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")
      received_messages = [] of {String, JSON::Any}

      # Subscribe and verify it works
      adapter.subscribe(topic) do |sid, msg|
        received_messages << {sid, msg}
      end

      adapter.publish(topic, sender_id, message)
      sleep(0.1.seconds)
      received_messages.size.should eq(1)

      # Unsubscribe and verify messages are no longer delivered
      adapter.unsubscribe(topic)
      received_messages.clear

      adapter.publish(topic, sender_id, message)
      sleep(0.1.seconds)
      received_messages.size.should eq(0)
    end

    it "handles unsubscribing from non-existent topics" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      # Should not raise an error
      adapter.unsubscribe("non_existent_topic")
    end
  end

  describe "#subscriber_count" do
    it "returns correct count of subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"

      adapter.subscriber_count(topic).should eq(0)

      # Add first subscriber
      adapter.subscribe(topic) do |_, _|
        # Empty listener
      end
      adapter.subscriber_count(topic).should eq(1)

      # Add second subscriber
      adapter.subscribe(topic) do |_, _|
        # Empty listener
      end
      adapter.subscriber_count(topic).should eq(2)

      # Unsubscribe all
      adapter.unsubscribe(topic)
      adapter.subscriber_count(topic).should eq(0)
    end

    it "returns 0 for non-existent topics" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      adapter.subscriber_count("non_existent_topic").should eq(0)
    end
  end

  describe "#has_subscribers?" do
    it "returns true when topic has subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"

      adapter.has_subscribers?(topic).should be_false

      adapter.subscribe(topic) do |_, _|
        # Empty listener
      end

      adapter.has_subscribers?(topic).should be_true
    end

    it "returns false for topics with no subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      adapter.has_subscribers?("empty_topic").should be_false
    end
  end

  describe "#active_topics" do
    it "returns list of topics with active subscribers" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      adapter.active_topics.should be_empty

      # Add subscribers to different topics
      adapter.subscribe("topic1") do |_, _|
        # Empty listener
      end

      adapter.subscribe("topic2") do |_, _|
        # Empty listener
      end

      active_topics = adapter.active_topics
      active_topics.should contain("topic1")
      active_topics.should contain("topic2")
      active_topics.size.should eq(2)
    end
  end

  describe "#stats" do
    it "returns correct statistics" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      stats = adapter.stats
      stats["total_topics"].should eq(0)
      stats["active_topics"].should eq(0)
      stats["total_subscribers"].should eq(0)

      # Add subscribers to topics
      adapter.subscribe("topic1") do |_, _|
        # Empty listener
      end

      adapter.subscribe("topic1") do |_, _|
        # Empty listener
      end

      adapter.subscribe("topic2") do |_, _|
        # Empty listener
      end

      stats = adapter.stats
      stats["total_topics"].should eq(2)
      stats["active_topics"].should eq(2)
      stats["total_subscribers"].should eq(3)
    end
  end

  describe "#unsubscribe_all" do
    it "removes all subscriptions" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new

      # Add multiple subscriptions
      adapter.subscribe("topic1") do |_, _|
        # Empty listener
      end

      adapter.subscribe("topic2") do |_, _|
        # Empty listener
      end

      adapter.subscriber_count("topic1").should eq(1)
      adapter.subscriber_count("topic2").should eq(1)

      # Clear all
      adapter.unsubscribe_all

      adapter.subscriber_count("topic1").should eq(0)
      adapter.subscriber_count("topic2").should eq(0)
      adapter.active_topics.should be_empty
    end
  end

  describe "error handling" do
    it "continues delivery to other subscribers when one fails" do
      adapter = Amber::Adapters::MemoryPubSubAdapter.new
      topic = "test_topic"
      sender_id = "sender_123"
      message = JSON.parse("{\"text\":\"Hello World\",\"timestamp\":123456}")
      successful_deliveries = 0
      failed_deliveries = 0

      # Add subscriber that will fail
      adapter.subscribe(topic) do |_, _|
        failed_deliveries += 1
        raise "Subscriber error"
      end

      # Add subscriber that will succeed
      adapter.subscribe(topic) do |_, _|
        successful_deliveries += 1
      end

      # Publish message
      adapter.publish(topic, sender_id, message)

      sleep(0.1.seconds)

      # Both subscribers should have been called
      failed_deliveries.should eq(1)
      successful_deliveries.should eq(1)
    end
  end
end
