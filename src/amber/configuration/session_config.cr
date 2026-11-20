require "yaml"

module Amber::Configuration
  class SessionConfig
    include YAML::Serializable

    LIST_OF_VALID_STORES = ["signed_cookie", "encrypted_cookie", "adapter", "redis"]

    property key : String = "amber.session"

    # Where sessions live. `signed_cookie` (the default) and `encrypted_cookie`
    # keep the session in the visitor's cookie, so the server holds nothing.
    # `adapter` keeps it on the server through `adapter`; `redis` is read the
    # same way.
    property store : String = "signed_cookie"
    property expires : Int32 = 0

    # The session adapter `store: adapter` uses: `memory` or a registered one.
    property adapter : String = "memory"

    # The most sessions the `memory` adapter keeps in one process. When it is
    # full, the session used longest ago is dropped to make room. It is read
    # once, when the memory adapter is first built.
    property max_memory_sessions : Int32 = Amber::Adapters::MemorySessionAdapter::DEFAULT_MAX_SESSIONS

    def initialize
    end

    def store_type : Symbol
      case @store
      when "signed_cookie"    then :signed_cookie
      when "adapter"          then :adapter
      when "redis"            then :redis
      when "encrypted_cookie" then :encrypted_cookie
      else                         :encrypted_cookie
      end
    end

    def validate! : Nil
      unless LIST_OF_VALID_STORES.includes?(@store)
        raise Amber::Exceptions::ConfigurationError.new(
          "session.store must be one of #{LIST_OF_VALID_STORES.join(", ")}, got '#{@store}'"
        )
      end

      if @max_memory_sessions < 1
        raise Amber::Exceptions::ConfigurationError.new(
          "session.max_memory_sessions must be at least 1, got #{@max_memory_sessions}"
        )
      end
    end
  end
end
