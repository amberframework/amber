require "yaml"

module Amber::Environment
  class Settings
    include YAML::Serializable

    alias SettingValue = String | Int32 | Bool | Nil

    struct SMTPSettings
      include YAML::Serializable

      property host : String = "127.0.0.1"
      property port : Int32 = 1025
      property enabled : Bool = false
      property username : String = ""
      property password : String = ""
      property tls : Bool = false

      def initialize
      end

      def self.from_hash(settings = {} of String => SettingValue) : self
        i = new
        settings.each do |key, value|
          case key
          when "host"     then i.host = value.as(String) if value.is_a?(String)
          when "port"     then i.port = value.as(Int32) if value.is_a?(Int32)
          when "enabled"  then i.enabled = value.as(Bool) if value.is_a?(Bool)
          when "username" then i.username = value.as(String) if value.is_a?(String)
          when "password" then i.password = value.as(String) if value.is_a?(String)
          when "tls"      then i.tls = value.as(Bool) if value.is_a?(Bool)
          end
        end
        i
      end
    end

    property database_url : String = ""
    property host : String = "localhost"
    property name : String = "Amber_App"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property secret_key_base : String = ""
    property previous_secrets : Array(String) = [] of String
    property secrets : Hash(String, String) = {} of String => String
    property ssl_key_file : String?
    property ssl_cert_file : String?

    @[YAML::Field(key: "logging")]
    property logging_config : Hash(String, String | Bool | Array(String)) = Logging::DEFAULTS

    @[YAML::Field(key: "auto_reload")]
    property? auto_reload : Bool = false

    @[YAML::Field(key: "session")]
    property session_config : Hash(String, Int32 | String) = {"key" => "amber.session", "store" => "signed_cookie", "expires" => 0, "adapter" => "memory"}

    # Backward compatibility setter
    def session=(value : Hash(String, Int32 | String))
      @session_config = value
    end

    @[YAML::Field(key: "pubsub")]
    property pubsub_config : Hash(String, String) = {"adapter" => "memory"}

    # Backward compatibility setter
    def pubsub=(value : Hash(String, String))
      @pubsub_config = value
    end

    property smtp : SMTPSettings = SMTPSettings.new

    property pipes : Hash(String, Hash(String, Hash(String, String | Int32 | Bool | Nil))) = {"static" => {"headers" => {} of String => SettingValue}}

    # The backing AppConfig for V2 subsection accessors.
    # Built lazily from V1 properties or set directly from V2 YAML loading.
    @[YAML::Field(ignore: true)]
    @_app_config : Amber::Configuration::AppConfig?

    def initialize
      @secret_key_base = Random::Secure.urlsafe_base64(32)
    end

    def session
      {
        :key     => @session_config["key"].to_s,
        :store   => session_store,
        :expires => @session_config["expires"].to_i,
        :adapter => @session_config["adapter"]?.try(&.to_s) || "memory",
      }
    end

    def pubsub
      {
        :adapter => @pubsub_config["adapter"]?.try(&.to_s) || "memory",
      }
    end

    def session_store
      case @session_config["store"].to_s
      when "signed_cookie" then :signed_cookie
      when "redis"         then :redis
      else
        :encrypted_cookie
      end
    end

    @_logging : Logging?

    def logging
      @_logging ||= Logging.new(@logging_config)
    end

    # Returns the jobs configuration.
    # This delegates to the Amber::Jobs module configuration.
    @[YAML::Field(ignore: true)]
    @_jobs : Amber::Jobs::Configuration?

    def jobs : Amber::Jobs::Configuration
      @_jobs ||= Amber::Jobs.configuration
    end

    # -- V2 Subsection Accessors --
    # These provide the new structured API: Amber.settings.server, Amber.settings.mailer, etc.
    # They build a V2 AppConfig from V1 flat properties when needed.

    # Returns the typed server configuration.
    def server : Amber::Configuration::ServerConfig
      to_app_config.server
    end

    # Returns the typed database configuration.
    def database : Amber::Configuration::DatabaseConfig
      to_app_config.database
    end

    # Returns the typed session configuration.
    def session_v2 : Amber::Configuration::SessionConfig
      to_app_config.session
    end

    # Returns the typed pubsub configuration.
    def pubsub_v2 : Amber::Configuration::PubSubConfig
      to_app_config.pubsub
    end

    # Returns the typed logging configuration.
    def logging_v2 : Amber::Configuration::LoggingConfig
      to_app_config.logging
    end

    # Returns the typed jobs configuration.
    def jobs_v2 : Amber::Configuration::JobsConfig
      to_app_config.jobs
    end

    # Returns the typed mailer configuration.
    def mailer : Amber::Configuration::MailerConfig
      to_app_config.mailer
    end

    # Returns the typed static files configuration.
    def static : Amber::Configuration::StaticConfig
      to_app_config.static
    end

    # Returns the full AppConfig, building it from V1 properties if needed.
    def to_app_config : Amber::Configuration::AppConfig
      @_app_config ||= build_app_config_from_v1
    end

    # Sets the backing AppConfig directly (used when loading V2 YAML).
    def app_config=(config : Amber::Configuration::AppConfig)
      @_app_config = config
    end

    # Retrieve a registered custom configuration section by key and type.
    def custom(key : Symbol, type : T.class) : T forall T
      to_app_config.custom(key, type)
    end

    # Build an AppConfig from V1 flat properties.
    private def build_app_config_from_v1 : Amber::Configuration::AppConfig
      config = Amber::Configuration::AppConfig.new
      config.name = @name

      config.server.host = @host
      config.server.port = @port
      config.server.port_reuse = @port_reuse
      config.server.process_count = @process_count
      config.server.secret_key_base = @secret_key_base
      config.server.ssl.key_file = @ssl_key_file
      config.server.ssl.cert_file = @ssl_cert_file

      config.database.url = @database_url

      config.session.key = @session_config["key"].to_s
      config.session.store = @session_config["store"].to_s
      config.session.expires = @session_config["expires"].to_i
      config.session.adapter = @session_config["adapter"]?.try(&.to_s) || "memory"

      config.pubsub.adapter = @pubsub_config["adapter"]?.try(&.to_s) || "memory"

      logging_val = @logging_config
      config.logging.severity = logging_val["severity"]?.try(&.to_s) || "debug"
      config.logging.colorize = logging_val["colorize"]?.try { |v| v.as(Bool) } || true
      config.logging.color = logging_val["color"]?.try(&.to_s) || "light_cyan"
      if filter = logging_val["filter"]?
        config.logging.filter = filter.as(Array(String))
      end
      if skip = logging_val["skip"]?
        config.logging.skip = skip.as(Array(String))
      end

      config.secrets = @secrets

      # Map static pipe headers
      if static_pipe = @pipes.dig?("static", "headers")
        headers = {} of String => String
        static_pipe.each do |k, v|
          headers[k] = v.to_s if v
        end
        config.static.headers = headers
      end

      config
    end
  end
end
