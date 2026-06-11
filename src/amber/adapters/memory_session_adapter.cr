require "./session_adapter"
require "uuid"

module Amber::Adapters
  # In-memory implementation of SessionAdapter.
  #
  # This adapter stores session data in memory using Hash structures and provides
  # TTL functionality through background cleanup. This is the default session adapter
  # and is suitable for development, testing, and single-instance applications.
  #
  # **Note**: Session data will be lost when the application restarts since
  # everything is stored in memory. For production applications that require
  # persistence or multi-instance deployments, consider using a database or
  # Redis-based adapter.
  #
  # ## Usage
  #
  # ```
  # # Configure in your application settings
  # config.session_adapter = Amber::Adapters::MemorySessionAdapter.new
  # ```
  class MemorySessionAdapter < SessionAdapter
    # Internal structure to store session data with expiration times
    private record SessionEntry, data : Hash(String, String), expires_at : Time?

    # Thread-safe session storage
    @sessions : Hash(String, SessionEntry)
    @mutex : Mutex
    @cleanup_running : Bool = false

    def initialize
      @sessions = Hash(String, SessionEntry).new
      @mutex = Mutex.new
      start_cleanup_task
    end

    # Retrieves a value for the given session and key
    def get(session_id : String, key : String) : String?
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return nil unless entry

        # Check if session has expired
        if expired?(entry)
          @sessions.delete(session_id)
          return nil
        end

        entry.data[key]?
      end
    end

    # Sets a value for the given session and key
    def set(session_id : String, key : String, value : String) : Nil
      @mutex.synchronize do
        entry = @sessions[session_id]?

        if entry && !expired?(entry)
          # Update existing session
          entry.data[key] = value
        else
          # Create new session entry
          @sessions[session_id] = SessionEntry.new(
            data: Hash{key => value},
            expires_at: nil
          )
        end
      end
    end

    # Deletes a specific key from a session
    def delete(session_id : String, key : String) : Nil
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return unless entry && !expired?(entry)

        entry.data.delete(key)
      end
    end

    # Completely destroys a session and all its data
    def destroy(session_id : String) : Nil
      @mutex.synchronize do
        @sessions.delete(session_id)
      end
    end

    # Checks if a key exists in the given session
    def exists?(session_id : String, key : String) : Bool
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return false unless entry && !expired?(entry)

        entry.data.has_key?(key)
      end
    end

    # Returns all keys for the given session
    def keys(session_id : String) : Array(String)
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return Array(String).new unless entry && !expired?(entry)

        entry.data.keys
      end
    end

    # Returns all values for the given session
    def values(session_id : String) : Array(String)
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return Array(String).new unless entry && !expired?(entry)

        entry.data.values
      end
    end

    # Returns all session data as a hash
    def to_hash(session_id : String) : Hash(String, String)
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return Hash(String, String).new unless entry && !expired?(entry)

        entry.data.dup
      end
    end

    # Checks if the session is empty
    def empty?(session_id : String) : Bool
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return true unless entry && !expired?(entry)

        entry.data.empty?
      end
    end

    # Sets an expiration time for the session
    def expire(session_id : String, seconds : Int32) : Nil
      @mutex.synchronize do
        entry = @sessions[session_id]?
        return unless entry

        @sessions[session_id] = SessionEntry.new(
          data: entry.data,
          expires_at: Time.utc + seconds.seconds
        )
      end
    end

    # Efficiently sets multiple key-value pairs in a single atomic operation
    def batch_set(session_id : String, hash : Hash(String, String)) : Nil
      @mutex.synchronize do
        entry = @sessions[session_id]?

        if entry && !expired?(entry)
          # Update existing session with new values
          hash.each { |key, value| entry.data[key] = value }
        else
          # Create new session entry with the provided hash
          @sessions[session_id] = SessionEntry.new(
            data: hash.dup,
            expires_at: nil
          )
        end
      end
    end

    # Performs bulk operations atomically
    def batch(session_id : String, &block : BatchOperations ->) : Nil
      @mutex.synchronize do
        operations = BatchOperations.new(session_id, self)
        yield operations
      end
    end

    # Checks if a session entry has expired
    private def expired?(entry : SessionEntry) : Bool
      if expires_at = entry.expires_at
        Time.utc > expires_at
      else
        false
      end
    end

    # Starts a background task to clean up expired sessions
    private def start_cleanup_task
      return if @cleanup_running
      @cleanup_running = true

      spawn do
        loop do
          sleep(60.seconds) # Cleanup every minute
          cleanup_expired_sessions
        end
      end
    end

    # Removes expired sessions from memory
    private def cleanup_expired_sessions
      @mutex.synchronize do
        @sessions.reject! { |_, entry| expired?(entry) }
      end
    end

    # Sets a value without mutex (for internal use in batch operations)
    protected def unsafe_set(session_id : String, key : String, value : String) : Nil
      entry = @sessions[session_id]?

      if entry && !expired?(entry)
        # Update existing session
        entry.data[key] = value
      else
        # Create new session entry
        @sessions[session_id] = SessionEntry.new(
          data: Hash{key => value},
          expires_at: nil
        )
      end
    end

    # Deletes a key without mutex (for internal use in batch operations)
    protected def unsafe_delete(session_id : String, key : String) : Nil
      entry = @sessions[session_id]?
      return unless entry && !expired?(entry)

      entry.data.delete(key)
    end

    # Sets expiration without mutex (for internal use in batch operations)
    protected def unsafe_expire(session_id : String, seconds : Int32) : Nil
      entry = @sessions[session_id]?
      return unless entry

      @sessions[session_id] = SessionEntry.new(
        data: entry.data,
        expires_at: Time.utc + seconds.seconds
      )
    end

    # Helper class for batch operations
    class BatchOperations < Amber::Adapters::SessionBatchOperations
      def initialize(@session_id : String, @adapter : MemorySessionAdapter)
      end

      def set(key : String, value : String) : Nil
        @adapter.unsafe_set(@session_id, key, value)
      end

      def delete(key : String) : Nil
        @adapter.unsafe_delete(@session_id, key)
      end

      def expire(seconds : Int32) : Nil
        @adapter.unsafe_expire(@session_id, seconds)
      end
    end
  end
end
