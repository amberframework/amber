require "yaml"

module Amber::Configuration
  class SessionConfig
    include YAML::Serializable

    property key : String = "amber.session"
    property store : String = "signed_cookie"
    property expires : Int32 = 0
    property adapter : String = "memory"

    def initialize
    end

    def store_type : Symbol
      case @store
      when "signed_cookie"    then :signed_cookie
      when "redis"            then :redis
      when "encrypted_cookie" then :encrypted_cookie
      else                         :encrypted_cookie
      end
    end

    def validate! : Nil
      valid_stores = ["signed_cookie", "encrypted_cookie", "redis"]
      unless valid_stores.includes?(@store)
        raise Amber::Exceptions::ConfigurationError.new(
          "session.store must be one of #{valid_stores.join(", ")}, got '#{@store}'"
        )
      end
    end
  end
end
