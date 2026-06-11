require "uuid"

module Amber::Router::Session
  # Session store implementation that uses the pluggable adapter system.
  #
  # This replaces the hardcoded Redis/Cookie stores with a flexible adapter-based
  # approach that allows users to implement custom session storage backends.
  #
  # The session adapter handles the low-level storage operations while this class
  # provides the higher-level session management logic including session ID
  # generation, cookie handling, and expiration.
  class AdapterSessionStore < AbstractStore
    @id : String?
    @is_changed : Bool = false
    getter adapter : Amber::Adapters::SessionAdapter
    property expires : Int32
    property key : String
    property session_id : String
    property cookies : Amber::Router::Cookies::Store

    def self.build(adapter : Amber::Adapters::SessionAdapter, cookies, session)
      new(adapter, cookies, session[:key].to_s, session[:expires].to_i)
    end

    def initialize(@adapter, @cookies, @key, @expires = 120)
      @session_id = current_session || "#{key}:#{id}"
    end

    def id
      @id ||= UUID.random.to_s
    end

    def changed?
      @is_changed
    end

    def destroy
      @is_changed = true
      adapter.destroy(session_id)
    end

    def [](key : String | Symbol)
      adapter.get(session_id, key.to_s)
    end

    def []?(key : String | Symbol)
      adapter.get(session_id, key.to_s)
    end

    def []=(key : String | Symbol, value)
      @is_changed = true
      adapter.set(session_id, key.to_s, value.to_s)
    end

    def has_key?(key : String | Symbol) : Bool
      adapter.exists?(session_id, key.to_s)
    end

    def keys
      adapter.keys(session_id)
    end

    def values
      adapter.values(session_id)
    end

    def to_h
      adapter.to_hash(session_id)
    end

    def update(hash : Hash(String | Symbol, String))
      @is_changed = true
      # Convert symbol keys to strings for consistency
      string_hash = hash.transform_keys(&.to_s)
      adapter.batch_set(session_id, string_hash)
    end

    def delete(key : String | Symbol)
      if has_key?(key.to_s)
        @is_changed = true
        adapter.delete(session_id, key.to_s)
      end
    end

    def fetch(key : String | Symbol, default = nil)
      adapter.get(session_id, key.to_s) || default
    end

    def empty?
      adapter.empty?(session_id)
    end

    # Regenerates the session ID to prevent session fixation attacks.
    # Copies all existing session data to a new session, destroys the old
    # session, and updates the cookie with the new session ID.
    #
    # This should be called after successful authentication or any privilege
    # escalation to ensure the user gets a fresh session ID.
    #
    # Returns the new session ID.
    def regenerate_id : String
      old_session_id = @session_id
      old_data = adapter.to_hash(old_session_id)

      @id = UUID.random.to_s
      @session_id = "#{key}:#{@id}"

      # Copy data to new session
      adapter.batch_set(@session_id, old_data) unless old_data.empty?

      # Set expiration on new session if applicable
      adapter.expire(@session_id, @expires) if @expires > 0

      # Destroy old session
      adapter.destroy(old_session_id)

      # Mark as changed so the new session ID cookie gets written
      @is_changed = true

      @session_id
    end

    # Resets the session TTL for sliding expiration.
    # Called on each request to extend the session lifetime when idle_timeout is configured.
    def touch
      adapter.expire(session_id, @expires) if @expires > 0
    end

    def set_session
      secure = !Amber.env.development? && !Amber.env.test?
      samesite = HTTP::Cookie::SameSite::Lax

      cookies.encrypted.set(key, session_id,
        expires: expires_at,
        http_only: true,
        secure: secure,
        samesite: samesite)

      # Set expiration on the session
      adapter.expire(session_id, @expires) if @expires > 0
    end

    def expires_at
      (Time.utc + expires.seconds) if @expires > 0
    end

    def current_session
      cookies.encrypted[key]
    end
  end
end
