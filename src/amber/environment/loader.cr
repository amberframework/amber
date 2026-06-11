module Amber::Environment
  class Loader
    def initialize(@environment : Amber::Environment::EnvType = Amber.env.to_s,
                   @path : String = Amber.path)
      raise Exceptions::Environment.new(@path, @environment) unless settings_file_exist?
    end

    def settings
      content = settings_content.to_s
      yaml_format = detect_format(content)

      case yaml_format
      when :v2
        load_v2_settings(content)
      else
        load_v1_settings(content)
      end
    end

    # Detect whether a YAML string uses the V1 flat format or the V2 nested format.
    #
    # V2 format has a "server" key that is a mapping (Hash).
    # V1 format has "host", "port" at the root level.
    def detect_format(yaml_content : String) : Symbol
      parsed = YAML.parse(yaml_content)
      if parsed["server"]?.try(&.as_h?)
        :v2
      else
        :v1
      end
    end

    private def load_v1_settings(content : String) : Settings
      settings = Settings.from_yaml(content)
      settings
    end

    private def load_v2_settings(content : String) : Settings
      app_config = Amber::Configuration::AppConfig.from_yaml(content)

      # Apply environment variable overrides
      Amber::Configuration::EnvOverride.apply_all(app_config)

      # Load any registered custom configs from the YAML
      load_custom_configs(content, app_config)

      # Build a Settings instance backed by the AppConfig
      settings = build_settings_from_app_config(app_config)
      settings
    end

    # Load custom configuration sections from the YAML content
    # and store them in the AppConfig.
    private def load_custom_configs(content : String, app_config : Amber::Configuration::AppConfig)
      parsed = YAML.parse(content)
      Amber::Configuration.custom_config_defaults.each do |key, _default|
        if yaml_node = parsed[key]?
          if loaded = Amber::Configuration.load_custom_from_yaml(key, yaml_node.to_yaml)
            app_config.custom_configs[key] = loaded
          end
        else
          # Use the default instance
          app_config.custom_configs[key] = Amber::Configuration.custom_config_defaults[key]
        end
      end
    end

    # Build a backward-compatible Settings instance from an AppConfig.
    private def build_settings_from_app_config(app_config : Amber::Configuration::AppConfig) : Settings
      settings = Settings.from_yaml("name: #{app_config.name}")
      settings.name = app_config.name
      settings.host = app_config.server.host
      settings.port = app_config.server.port
      settings.port_reuse = app_config.server.port_reuse
      settings.process_count = app_config.server.process_count
      settings.secret_key_base = app_config.server.secret_key_base
      settings.ssl_key_file = app_config.server.ssl.key_file
      settings.ssl_cert_file = app_config.server.ssl.cert_file
      settings.database_url = app_config.database.url
      settings.secrets = app_config.secrets

      settings.session = {
        "key"     => app_config.session.key,
        "store"   => app_config.session.store,
        "expires" => app_config.session.expires,
        "adapter" => app_config.session.adapter,
      }

      settings.pubsub = {
        "adapter" => app_config.pubsub.adapter,
      }

      settings.logging_config = {
        "severity" => app_config.logging.severity,
        "colorize" => app_config.logging.colorize,
        "color"    => app_config.logging.color,
        "filter"   => app_config.logging.filter,
        "skip"     => app_config.logging.skip,
      }

      # Map static config back to pipes format
      if !app_config.static.headers.empty?
        static_headers = {} of String => Settings::SettingValue
        app_config.static.headers.each do |k, v|
          static_headers[k] = v
        end
        settings.pipes = {"static" => {"headers" => static_headers}}
      end

      # Store the AppConfig reference for V2 subsection accessors
      settings.app_config = app_config

      settings
    end

    private def settings_content
      if File.exists?(yml_settings_file)
        File.read(yml_settings_file)
      elsif File.exists?(enc_settings_file)
        Support::FileEncryptor.read_as_string(enc_settings_file)
      end
    end

    private def yml_settings_file
      @yml_settings ||= File.expand_path("#{@path}/#{@environment}.yml")
    end

    private def enc_settings_file
      @enc_settings ||= File.expand_path("#{@path}/.#{@environment}.enc")
    end

    private def settings_file_exist?
      File.exists?(yml_settings_file) || File.exists?(enc_settings_file)
    end
  end
end
