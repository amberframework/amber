require "yaml"

module Amber::Configuration
  class SSLConfig
    include YAML::Serializable

    property key_file : String? = nil
    property cert_file : String? = nil

    def initialize
    end

    def is_enabled? : Bool
      !key_file.nil? && !cert_file.nil?
    end
  end

  class ServerConfig
    include YAML::Serializable

    property host : String = "localhost"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property secret_key_base : String = ""

    @[YAML::Field(key: "ssl")]
    property ssl : SSLConfig = SSLConfig.new

    def initialize
    end

    def validate!(environment : Amber::Environment::Env? = nil) : Nil
      unless @port.in?(1..65535)
        raise Amber::Exceptions::ConfigurationError.new(
          "server.port must be between 1 and 65535, got #{@port}"
        )
      end

      unless @process_count >= 1
        raise Amber::Exceptions::ConfigurationError.new(
          "server.process_count must be at least 1, got #{@process_count}"
        )
      end

      if environment && environment.production?
        if @secret_key_base.empty?
          raise Amber::Exceptions::ConfigurationError.new(
            "server.secret_key_base must be set in production"
          )
        end
      end

      if !@secret_key_base.empty? && @secret_key_base.size < 32
        raise Amber::Exceptions::ConfigurationError.new(
          "server.secret_key_base should be at least 32 characters, got #{@secret_key_base.size}"
        )
      end

      if ssl.is_enabled?
        if ssl.key_file && !File.exists?(ssl.key_file.not_nil!)
          raise Amber::Exceptions::ConfigurationError.new(
            "server.ssl.key_file does not exist: #{ssl.key_file}"
          )
        end
        if ssl.cert_file && !File.exists?(ssl.cert_file.not_nil!)
          raise Amber::Exceptions::ConfigurationError.new(
            "server.ssl.cert_file does not exist: #{ssl.cert_file}"
          )
        end
      end
    end
  end
end
