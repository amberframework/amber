module Amber::Adapters
  # Abstract base class for session storage adapters.
  #
  # All session storage implementations should inherit from this class and implement
  # the required abstract methods. This allows the Amber framework to work with
  # any backend storage system (Redis, database, memory, etc.) through a unified interface.
  #
  # Example implementation:
  #
  # ```
  # class CustomSessionAdapter < Amber::Adapters::SessionAdapter
  #   def initialize(@connection : MyStorageConnection)
  #   end
  #
  #   def get(session_id : String, key : String) : String?
  #     @connection.fetch("#{session_id}:#{key}")
  #   end
  #
  #   # ... implement other abstract methods
  # end
  # ```
  abstract class SessionAdapter
    # Core session data operations

    # Retrieves a value for the given key within the specified session.
    # Returns the value as a String, or nil if the key doesn't exist.
    abstract def get(session_id : String, key : String) : String?

    # Sets a value for the given key within the specified session.
    abstract def set(session_id : String, key : String, value : String) : Nil

    # Deletes a specific key from the session.
    # Should be a no-op if the key doesn't exist.
    abstract def delete(session_id : String, key : String) : Nil

    # Completely destroys the session and all its data.
    abstract def destroy(session_id : String) : Nil

    # Session metadata and query operations

    # Checks if a specific key exists within the session.
    abstract def exists?(session_id : String, key : String) : Bool

    # Returns all keys present in the session.
    abstract def keys(session_id : String) : Array(String)

    # Returns all values present in the session.
    abstract def values(session_id : String) : Array(String)

    # Returns the entire session as a Hash.
    abstract def to_hash(session_id : String) : Hash(String, String)

    # Checks if the session is empty (contains no keys).
    # Note: Some implementations may consider a session with only metadata
    # (like session_id) as empty for application purposes.
    abstract def empty?(session_id : String) : Bool

    # Session lifecycle operations

    # Sets an expiration time for the session in seconds from now.
    # A value of 0 or negative should remove any existing expiration.
    abstract def expire(session_id : String, seconds : Int32) : Nil

    # Efficiently sets multiple key-value pairs in a single operation.
    # This should be atomic where possible to maintain session consistency.
    abstract def batch_set(session_id : String, hash : Hash(String, String)) : Nil

    # Provides a way to perform multiple operations in a single atomic block.
    # This is useful for adapters that support pipelining or transactions.
    abstract def batch(session_id : String, &block : SessionBatchOperations ->) : Nil

    # Optional lifecycle methods with default implementations

    # Called when the adapter is being shut down.
    # Override this method to perform cleanup operations like closing connections.
    def close : Nil
      # Default implementation does nothing
    end

    # Called to check if the adapter is healthy and ready to handle requests.
    # Override this method to implement health checks for your storage backend.
    def healthy? : Bool
      true
    end
  end

  abstract class SessionBatchOperations
    abstract def set(key : String, value : String) : Nil
    abstract def delete(key : String) : Nil
    abstract def expire(seconds : Int32) : Nil
  end
end
