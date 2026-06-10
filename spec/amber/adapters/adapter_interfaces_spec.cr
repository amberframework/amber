require "../../spec_helper"

# Test implementations to verify the adapter interfaces
class TestSessionAdapter < Amber::Adapters::SessionAdapter
  def get(session_id : String, key : String) : String?
    nil
  end

  def set(session_id : String, key : String, value : String) : Nil
  end

  def delete(session_id : String, key : String) : Nil
  end

  def destroy(session_id : String) : Nil
  end

  def exists?(session_id : String, key : String) : Bool
    false
  end

  def keys(session_id : String) : Array(String)
    Array(String).new
  end

  def values(session_id : String) : Array(String)
    Array(String).new
  end

  def to_hash(session_id : String) : Hash(String, String)
    Hash(String, String).new
  end

  def empty?(session_id : String) : Bool
    true
  end

  def expire(session_id : String, seconds : Int32) : Nil
  end

  def batch_set(session_id : String, hash : Hash(String, String)) : Nil
  end

  def batch(session_id : String, &block : Amber::Adapters::SessionBatchOperations ->) : Nil
  end
end

class TestPubSubAdapter < Amber::Adapters::PubSubAdapter
  def publish(topic : String, sender_id : String, message : JSON::Any) : Nil
  end

  def subscribe(topic : String, &block : (String, JSON::Any) -> Nil) : Nil
  end

  def unsubscribe(topic : String) : Nil
  end

  def unsubscribe_all : Nil
  end

  def close : Nil
  end
end

describe "Adapter Interfaces" do
  describe Amber::Adapters::SessionAdapter do
    it "defines the correct abstract interface" do
      # This test verifies that all required methods are defined as abstract
      # by attempting to create concrete implementations

      adapter = TestSessionAdapter.new

      # Test that all methods are callable with correct signatures
      adapter.get("session_1", "key").should be_nil
      adapter.exists?("session_1", "key").should be_false
      adapter.keys("session_1").should be_empty
      adapter.values("session_1").should be_empty
      adapter.to_hash("session_1").should be_empty
      adapter.empty?("session_1").should be_true
      adapter.healthy?.should be_true

      # Test that void methods don't raise
      adapter.set("session_1", "key", "value")
      adapter.delete("session_1", "key")
      adapter.destroy("session_1")
      adapter.expire("session_1", 60)
      adapter.batch_set("session_1", {"key" => "value"})
      adapter.close
    end
  end

  describe Amber::Adapters::PubSubAdapter do
    it "defines the correct abstract interface" do
      # This test verifies that all required methods are defined as abstract
      # by attempting to create concrete implementations

      adapter = TestPubSubAdapter.new

      # Test that all methods are callable with correct signatures
      message = JSON.parse(%({"test": "message"}))

      adapter.healthy?.should be_true
      adapter.subscriber_count.should eq(0)
      adapter.active_topics.should be_empty

      # Test that void methods don't raise
      adapter.publish("test_topic", "sender_123", message)
      adapter.subscribe("test_topic") { |sender_id, msg| }
      adapter.unsubscribe("test_topic")
      adapter.unsubscribe_all
      adapter.close
    end
  end
end
