require "./adapters/session_adapter"
require "./adapters/pubsub_adapter"
require "./adapters/memory_session_adapter"
require "./adapters/memory_pubsub_adapter"
require "./adapters/adapter_factory"

module Amber::Adapters
  # This module contains all the abstract adapter interfaces for Amber framework components.
  #
  # ## Available Adapters
  #
  # ### SessionAdapter
  # Abstract interface for session storage backends. Implementations can use any storage
  # system (database, Redis, in-memory, file-based, etc.) as long as they provide the
  # required session operations.
  #
  # ### PubSubAdapter
  # Abstract interface for pub/sub messaging backends used by WebSocket channels.
  # Implementations can use any messaging system (Redis pub/sub, message queues,
  # in-memory broadcasting, etc.) as long as they provide publish/subscribe functionality.
  #
  # ## Built-in Adapters
  #
  # Amber provides in-memory implementations as the default adapters:
  # - `MemorySessionAdapter` - Thread-safe in-memory session storage with expiration
  # - `MemoryPubSubAdapter` - In-process pub/sub messaging for WebSocket channels
  #
  # ## Creating Custom Adapters
  #
  # To create a custom adapter, inherit from one of the abstract base classes and
  # implement all the required abstract methods:
  #
  # ```
  # class MyCustomSessionAdapter < Amber::Adapters::SessionAdapter
  #   def initialize(@my_storage : MyStorageSystem)
  #   end
  #
  #   def get(session_id : String, key : String) : String?
  #     @my_storage.fetch("sessions:#{session_id}:#{key}")
  #   end
  #
  #   # ... implement other required methods
  # end
  # ```
  #
  # ## Configuration
  #
  # Configure adapters in your application settings:
  #
  # ```yaml
  # # config/environments/development.yml
  # session:
  #   adapter: "memory"  # Use built-in memory adapter
  #   # OR
  #   adapter: "custom"  # Use your registered custom adapter
  #
  # pubsub:
  #   adapter: "memory"  # Use built-in memory adapter
  #   # OR
  #   adapter: "custom"  # Use your registered custom adapter
  # ```
  #
  # Then register your custom adapters:
  #
  # ```
  # # In your application initialization
  # Amber::Adapters::AdapterFactory.register_session_adapter("custom") do
  #   MyCustomSessionAdapter.new(my_storage)
  # end
  #
  # Amber::Adapters::AdapterFactory.register_pubsub_adapter("custom") do
  #   MyCustomPubSubAdapter.new(my_broker)
  # end
  # ```
end
