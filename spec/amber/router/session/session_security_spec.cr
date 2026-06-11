require "../../../spec_helper"

# Mock encrypted store for security testing
class SecurityMockEncryptedStore
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

# Mock cookies store for security testing
class SecurityMockCookiesStore < Amber::Router::Cookies::Store
  getter mock_encrypted

  def initialize
    super(host: "localhost", secret: "test_secret_for_session_security_specs")
    @mock_encrypted = SecurityMockEncryptedStore.new
  end

  def encrypted
    @mock_encrypted
  end
end

describe "Session Security Improvements" do
  describe "Session Fixation Prevention" do
    it "regenerates session ID and migrates data" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      # Set some session data
      store["user_id"] = "123"
      store["username"] = "testuser"

      old_session_id = store.session_id

      # Regenerate the session ID
      new_session_id = store.regenerate_id

      # Session ID should be different
      new_session_id.should_not eq(old_session_id)
      store.session_id.should eq(new_session_id)

      # Data should be migrated to the new session
      store["user_id"].should eq("123")
      store["username"].should eq("testuser")
    end

    it "destroys the old session after regeneration" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store["key"] = "value"
      old_session_id = store.session_id

      store.regenerate_id

      # Old session should be destroyed in the adapter
      adapter.get(old_session_id, "key").should be_nil
      adapter.empty?(old_session_id).should be_true
    end

    it "marks the session as changed after regeneration" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store.changed?.should be_false

      store.regenerate_id

      store.changed?.should be_true
    end

    it "generates a new UUID format session ID" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      new_session_id = store.regenerate_id

      new_session_id.should start_with("test.session:")
      # The UUID part should be 36 characters (8-4-4-4-12)
      uuid_part = new_session_id.sub("test.session:", "")
      uuid_part.size.should eq(36)
    end

    it "handles regeneration with empty session" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      old_session_id = store.session_id
      new_session_id = store.regenerate_id

      new_session_id.should_not eq(old_session_id)
      store.empty?.should be_true
    end
  end

  describe "AdapterSessionStore#changed? tracks actual changes" do
    it "returns false when no modifications are made" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store.changed?.should be_false
    end

    it "returns true after setting a value" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store["key"] = "value"
      store.changed?.should be_true
    end

    it "returns true after deleting a key that exists" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store["key"] = "value"
      store.delete("key")
      store.changed?.should be_true
    end

    it "does not report changed after deleting a key that does not exist" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      # changed? is false because the key did not exist so nothing happened
      store.delete("nonexistent")
      store.changed?.should be_false
    end

    it "returns true after destroying session" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store.destroy
      store.changed?.should be_true
    end

    it "returns true after bulk update" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store.update({"k" => "v"})
      store.changed?.should be_true
    end

    it "returns true after regenerate_id" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store.regenerate_id
      store.changed?.should be_true
    end
  end

  describe "Sliding Expiration" do
    it "touch method resets TTL on the session" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 3600)

      store["key"] = "value"

      # Touch should not raise and should reset TTL
      store.touch
      store["key"].should eq("value")
    end

    it "touch does nothing when expires is 0" do
      adapter = Amber::Adapters::MemorySessionAdapter.new
      cookies = SecurityMockCookiesStore.new
      store = Amber::Router::Session::AdapterSessionStore.new(adapter, cookies, "test.session", 0)

      store["key"] = "value"

      # Should not raise
      store.touch
      store["key"].should eq("value")
    end
  end
end
