require "../../spec_helper"

describe Amber::Adapters::MemorySessionAdapter do
  describe "#get and #set" do
    it "stores and retrieves values" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.get(session_id, "key1").should eq("value1")
    end

    it "returns nil for non-existent keys" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.get(session_id, "non_existent").should be_nil
    end

    it "returns nil for non-existent sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.get("non_existent_session", "key1").should be_nil
    end

    it "updates existing values" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key1", "updated_value")
      adapter.get(session_id, "key1").should eq("updated_value")
    end
  end

  describe "#exists?" do
    it "returns true for existing keys" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.exists?(session_id, "key1").should be_true
    end

    it "returns false for non-existent keys" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.exists?(session_id, "non_existent").should be_false
    end

    it "returns false for non-existent sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.exists?("non_existent_session", "key1").should be_false
    end
  end

  describe "#delete" do
    it "removes specific keys" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key2", "value2")

      adapter.delete(session_id, "key1")

      adapter.exists?(session_id, "key1").should be_false
      adapter.exists?(session_id, "key2").should be_true
    end

    it "handles deletion of non-existent keys gracefully" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.delete(session_id, "non_existent")
      # Should not raise an error
    end
  end

  describe "#destroy" do
    it "removes entire sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key2", "value2")

      adapter.destroy(session_id)

      adapter.exists?(session_id, "key1").should be_false
      adapter.exists?(session_id, "key2").should be_false
      adapter.empty?(session_id).should be_true
    end
  end

  describe "#keys" do
    it "returns all keys for a session" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key2", "value2")
      adapter.set(session_id, "key3", "value3")

      keys = adapter.keys(session_id)
      keys.should contain("key1")
      keys.should contain("key2")
      keys.should contain("key3")
      keys.size.should eq(3)
    end

    it "returns empty array for non-existent sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.keys("non_existent_session").should be_empty
    end
  end

  describe "#values" do
    it "returns all values for a session" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key2", "value2")
      adapter.set(session_id, "key3", "value3")

      values = adapter.values(session_id)
      values.should contain("value1")
      values.should contain("value2")
      values.should contain("value3")
      values.size.should eq(3)
    end

    it "returns empty array for non-existent sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.values("non_existent_session").should be_empty
    end
  end

  describe "#to_hash" do
    it "returns session data as hash" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.set(session_id, "key2", "value2")

      hash = adapter.to_hash(session_id)
      hash["key1"].should eq("value1")
      hash["key2"].should eq("value2")
      hash.size.should eq(2)
    end

    it "returns empty hash for non-existent sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.to_hash("non_existent_session").should be_empty
    end
  end

  describe "#empty?" do
    it "returns true for sessions with no data" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.empty?(session_id).should be_true
    end

    it "returns false for sessions with data" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.empty?(session_id).should be_false
    end

    it "returns true after all keys are deleted" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.delete(session_id, "key1")
      adapter.empty?(session_id).should be_true
    end
  end

  describe "#expire" do
    it "sets expiration for sessions" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.set(session_id, "key1", "value1")
      adapter.expire(session_id, 1) # 1 second TTL

      # Should still be accessible immediately
      adapter.get(session_id, "key1").should eq("value1")

      # Wait for expiration
      sleep(1.1.seconds)

      # Should be expired now
      adapter.get(session_id, "key1").should be_nil
      adapter.exists?(session_id, "key1").should be_false
    end

    it "handles expiration of non-existent sessions gracefully" do
      adapter = Amber::Adapters::MemorySessionAdapter.new

      adapter.expire("non_existent_session", 1)
      # Should not raise an error
    end
  end

  describe "#batch_set" do
    it "sets multiple key-value pairs atomically" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      data = {"key1" => "value1", "key2" => "value2", "key3" => "value3"}
      adapter.batch_set(session_id, data)

      adapter.get(session_id, "key1").should eq("value1")
      adapter.get(session_id, "key2").should eq("value2")
      adapter.get(session_id, "key3").should eq("value3")
    end
  end

  describe "#batch" do
    it "performs multiple operations atomically" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      session_id = "test_session_123"

      adapter.batch(session_id) do |operations|
        operations.set("key1", "value1")
        operations.set("key2", "value2")
        operations.expire(60)
      end

      adapter.get(session_id, "key1").should eq("value1")
      adapter.get(session_id, "key2").should eq("value2")
    end
  end
end
