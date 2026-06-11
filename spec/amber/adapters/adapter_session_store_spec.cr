require "../../spec_helper"

# Mock encrypted store for testing
class MockEncryptedStore
  def initialize
    @data = Hash(String, String).new
  end

  def [](key)
    @data[key]?
  end

  def set(key : String, value : String, **options)
    @data[key] = value
  end
end

# Mock cookies store that extends the actual store
class MockCookiesStore < Amber::Router::Cookies::Store
  getter mock_encrypted

  def initialize
    super(host: "localhost", secret: "test_secret")
    @mock_encrypted = MockEncryptedStore.new
  end

  def encrypted
    @mock_encrypted
  end
end

describe Amber::Router::Session::AdapterSessionStore do
  describe "with memory adapter" do
    describe "basic operations" do
      it "stores and retrieves values" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store["key1"].should eq("value1")
      end

      it "checks if key exists" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store.has_key?("key1").should be_true
        store.has_key?("key2").should be_false
      end

      it "returns nil for non-existent keys with []?" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"]?.should be_nil
        store["key1"] = "value1"
        store["key1"]?.should eq("value1")
      end

      it "returns nil for non-existent keys with []" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"].should be_nil
      end

      it "deletes keys" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store.has_key?("key1").should be_true

        store.delete("key1")
        store.has_key?("key1").should be_false
      end

      it "fetches with default value" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store.fetch("key1", "default").should eq("default")
        store["key1"] = "value1"
        store.fetch("key1", "default").should eq("value1")
      end
    end

    describe "bulk operations" do
      it "returns all keys" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store["key2"] = "value2"

        keys = store.keys
        keys.should contain("key1")
        keys.should contain("key2")
      end

      it "returns all values" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store["key2"] = "value2"

        values = store.values
        values.should contain("value1")
        values.should contain("value2")
      end

      it "returns hash representation" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store["key2"] = "value2"

        hash = store.to_h
        hash["key1"].should eq("value1")
        hash["key2"].should eq("value2")
      end

      it "updates multiple values at once" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        update_hash = {"key1" => "value1", "key2" => "value2"}
        store.update(update_hash)

        store["key1"].should eq("value1")
        store["key2"].should eq("value2")
      end

      it "handles symbol keys in update" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        update_hash = {:key1 => "value1", :key2 => "value2"}
        store.update(update_hash)

        store["key1"].should eq("value1")
        store["key2"].should eq("value2")
      end
    end

    describe "session lifecycle" do
      it "checks if session is empty" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store.empty?.should be_true
        store["key1"] = "value1"
        store.empty?.should be_false
      end

      it "destroys session" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store["key2"] = "value2"
        store.empty?.should be_false

        store.destroy
        store.empty?.should be_true
      end

      it "reports as not changed when no modifications are made" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store.changed?.should be_false
      end

      it "reports as changed after setting a value" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store.changed?.should be_true
      end

      it "reports as changed after deleting a value" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["key1"] = "value1"
        store.delete("key1")
        store.changed?.should be_true
      end

      it "reports as changed after destroy" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store.destroy
        store.changed?.should be_true
      end

      it "reports as changed after update" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store.update({"key1" => "value1"})
        store.changed?.should be_true
      end

      it "generates unique session IDs" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new

        store1 = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)
        store2 = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store1.session_id.should_not eq(store2.session_id)
      end
    end

    describe "expiration handling" do
      it "calculates expires_at correctly" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        current_time = Time.utc
        store_with_expiry = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        expires_at = store_with_expiry.expires_at
        expires_at.should_not be_nil
        expires_at.should be_a(Time)
        expires_at.not_nil!.should be > current_time
        expires_at.not_nil!.should be < current_time + 3700.seconds
      end

      it "returns nil for expires_at when no expiration" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store_no_expiry = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 0)
        store_no_expiry.expires_at.should be_nil
      end
    end

    describe "cookie integration" do
      it "uses current session from cookies if available" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new

        # Simulate existing session in cookies
        cookies.encrypted.set("test.session", "existing_session_id")

        store_with_existing = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)
        store_with_existing.session_id.should eq("existing_session_id")
      end

      it "creates new session ID when no cookie exists" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new

        new_store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "new.session", 3600)
        new_store.session_id.should start_with("new.session:")
      end
    end

    describe "type conversions" do
      it "converts values to strings when storing" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store["int_key"] = 42
        store["bool_key"] = true
        store["float_key"] = 3.14

        # Values should be stored as strings
        store["int_key"].should eq("42")
        store["bool_key"].should eq("true")
        store["float_key"].should eq("3.14")
      end

      it "handles symbol keys consistently" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

        store[:symbol_key] = "value"
        store["symbol_key"].should eq("value")
        store[:symbol_key].should eq("value")

        store.has_key?(:symbol_key).should be_true
        store.has_key?("symbol_key").should be_true
      end
    end

    describe "build method" do
      it "creates store instance with correct configuration" do
        adapter = Amber::Adapters::MemorySessionAdapter.new
        cookies = MockCookiesStore.new
        session_config = {key: "test.session", expires: 1800}
        built_store = Amber::Router::Session::AdapterSessionStore.build(adapter, cookies, session_config)

        built_store.key.should eq("test.session")
        built_store.expires.should eq(1800)
        built_store.adapter.should eq(adapter)
        built_store.cookies.should eq(cookies)
      end
    end
  end
end
