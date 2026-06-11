require "../../spec_helper"

describe Amber::Adapters::AdapterFactory do
  # Reset the factory before each test to ensure clean state
  before_each do
    # We need to reset the initialized flag and clear any custom adapters
    # This is a bit of a hack but necessary for testing
    {% if @type.class.has_method?("clear_for_testing") %}
      Amber::Adapters::AdapterFactory.clear_for_testing
    {% end %}
  end

  describe "built-in adapters" do
    describe "session adapters" do
      it "creates memory session adapter" do
        adapter = Amber::Adapters::AdapterFactory.create_session_adapter("memory")
        adapter.should be_a(Amber::Adapters::MemorySessionAdapter)
      end

      it "lists memory as available session adapter" do
        adapters = Amber::Adapters::AdapterFactory.available_session_adapters
        adapters.should contain("memory")
      end

      it "checks if memory session adapter is registered" do
        Amber::Adapters::AdapterFactory.session_adapter_registered?("memory").should be_true
      end

      it "raises error for unknown session adapter" do
        expect_raises(ArgumentError, /Unknown session adapter: unknown/) do
          Amber::Adapters::AdapterFactory.create_session_adapter("unknown")
        end
      end
    end

    describe "pubsub adapters" do
      it "creates memory pubsub adapter" do
        adapter = Amber::Adapters::AdapterFactory.create_pubsub_adapter("memory")
        adapter.should be_a(Amber::Adapters::MemoryPubSubAdapter)
      end

      it "lists memory as available pubsub adapter" do
        adapters = Amber::Adapters::AdapterFactory.available_pubsub_adapters
        adapters.should contain("memory")
      end

      it "checks if memory pubsub adapter is registered" do
        Amber::Adapters::AdapterFactory.pubsub_adapter_registered?("memory").should be_true
      end

      it "raises error for unknown pubsub adapter" do
        expect_raises(ArgumentError, /Unknown pub\/sub adapter: unknown/) do
          Amber::Adapters::AdapterFactory.create_pubsub_adapter("unknown")
        end
      end
    end
  end

  describe "custom adapter registration" do
    describe "session adapters" do
      it "registers custom session adapter with proc" do
        custom_adapter = Amber::Adapters::MemorySessionAdapter.new
        factory = -> { custom_adapter.as(Amber::Adapters::SessionAdapter) }

        Amber::Adapters::AdapterFactory.register_session_adapter("custom", factory)

        created_adapter = Amber::Adapters::AdapterFactory.create_session_adapter("custom")
        created_adapter.should eq(custom_adapter)
      end

      it "registers custom session adapter with block" do
        Amber::Adapters::AdapterFactory.register_session_adapter("custom") do
          Amber::Adapters::MemorySessionAdapter.new.as(Amber::Adapters::SessionAdapter)
        end

        adapter = Amber::Adapters::AdapterFactory.create_session_adapter("custom")
        adapter.should be_a(Amber::Adapters::MemorySessionAdapter)
      end

      it "lists custom session adapter in available adapters" do
        Amber::Adapters::AdapterFactory.register_session_adapter("custom") do
          Amber::Adapters::MemorySessionAdapter.new.as(Amber::Adapters::SessionAdapter)
        end

        adapters = Amber::Adapters::AdapterFactory.available_session_adapters
        adapters.should contain("custom")
      end

      it "checks if custom session adapter is registered" do
        Amber::Adapters::AdapterFactory.register_session_adapter("custom") do
          Amber::Adapters::MemorySessionAdapter.new.as(Amber::Adapters::SessionAdapter)
        end

        Amber::Adapters::AdapterFactory.session_adapter_registered?("custom").should be_true
      end
    end

    describe "pubsub adapters" do
      it "registers custom pubsub adapter with proc" do
        custom_adapter = Amber::Adapters::MemoryPubSubAdapter.new
        factory = -> { custom_adapter.as(Amber::Adapters::PubSubAdapter) }

        Amber::Adapters::AdapterFactory.register_pubsub_adapter("custom", factory)

        created_adapter = Amber::Adapters::AdapterFactory.create_pubsub_adapter("custom")
        created_adapter.should eq(custom_adapter)
      end

      it "registers custom pubsub adapter with block" do
        Amber::Adapters::AdapterFactory.register_pubsub_adapter("custom") do
          Amber::Adapters::MemoryPubSubAdapter.new.as(Amber::Adapters::PubSubAdapter)
        end

        adapter = Amber::Adapters::AdapterFactory.create_pubsub_adapter("custom")
        adapter.should be_a(Amber::Adapters::MemoryPubSubAdapter)
      end

      it "lists custom pubsub adapter in available adapters" do
        Amber::Adapters::AdapterFactory.register_pubsub_adapter("custom") do
          Amber::Adapters::MemoryPubSubAdapter.new.as(Amber::Adapters::PubSubAdapter)
        end

        adapters = Amber::Adapters::AdapterFactory.available_pubsub_adapters
        adapters.should contain("custom")
      end

      it "checks if custom pubsub adapter is registered" do
        Amber::Adapters::AdapterFactory.register_pubsub_adapter("custom") do
          Amber::Adapters::MemoryPubSubAdapter.new.as(Amber::Adapters::PubSubAdapter)
        end

        Amber::Adapters::AdapterFactory.pubsub_adapter_registered?("custom").should be_true
      end
    end
  end

  describe "adapter creation with options" do
    it "creates session adapter with options (currently unused but for future extensibility)" do
      adapter = Amber::Adapters::AdapterFactory.create_session_adapter("memory", timeout: 30)
      adapter.should be_a(Amber::Adapters::MemorySessionAdapter)
    end

    it "creates pubsub adapter with options (currently unused but for future extensibility)" do
      adapter = Amber::Adapters::AdapterFactory.create_pubsub_adapter("memory", pool_size: 10)
      adapter.should be_a(Amber::Adapters::MemoryPubSubAdapter)
    end
  end
end
