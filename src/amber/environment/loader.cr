require "levenshtein"

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
      check_v1_listener_settings!(content)
      check_v1_security_headers!(content)
      settings = Settings.from_yaml(content)
      # V1 files keep their flat format, but request parameter limits are a
      # security boundary: apply the same overrides and validation as V2.
      Amber::Configuration::EnvOverride.apply_params(settings.params_config)
      settings.params_config.validate!
      settings
    end

    # Settings the flat V1 format cannot carry: in a V1 file they would be
    # dropped without a word, leaving the defaults in force.
    LIST_OF_V2_ONLY_SERVER_KEYS = %w(trusted_proxies trusted_proxy_headers unix_socket)

    # Raises `Amber::Exceptions::ConfigurationError` when a V1 file names a
    # `server.trusted_proxies`, `server.trusted_proxy_headers` or
    # `server.unix_socket` setting, at its top level or through an
    # `AMBER_SERVER_*` variable: an application that set one would keep
    # serving with the defaults (for `unix_socket`, on TCP).
    private def check_v1_listener_settings!(content : String) : Nil
      list_of_top_level_keys = YAML.parse(content).as_h?.try(&.keys.map(&.to_s)) || [] of String
      list_of_names = LIST_OF_V2_ONLY_SERVER_KEYS.select do |key|
        list_of_top_level_keys.includes?(key) || ENV.has_key?("AMBER_SERVER_#{key.upcase}")
      end
      return if list_of_names.empty?

      raise Amber::Exceptions::ConfigurationError.new(
        "server.#{list_of_names.join(", server.")} needs the V2 settings format (a nested `server:` section); " \
        "move #{@path}/#{@environment}.yml to V2 to set it"
      )
    end

    # The flat V1 format has no `security_headers` section, so its values
    # and `AMBER_SECURITY_HEADERS_*` overrides would be dropped without a
    # word. Raises `Amber::Exceptions::ConfigurationError` when either is
    # present, including a key one or two letters from `security_headers`.
    private def check_v1_security_headers!(content : String) : Nil
      list_of_top_level_keys = YAML.parse(content).as_h?.try(&.keys.map(&.to_s)) || [] of String
      sets_section = list_of_top_level_keys.any? do |key|
        !Levenshtein.find(key, ["security_headers"], tolerance: 2).nil?
      end
      sets_override = ENV.keys.any?(&.starts_with?("AMBER_SECURITY_HEADERS_"))
      return unless sets_section || sets_override

      raise Amber::Exceptions::ConfigurationError.new(
        "security_headers needs the V2 settings format (a nested `server:` section); " \
        "move #{@path}/#{@environment}.yml to V2 to set it"
      )
    end

    # Raises `Amber::Exceptions::ConfigurationError` for a top-level key that
    # is one or two letters from a section name, such as `security_headders`:
    # the section it meant would keep its defaults without a word. Other
    # unknown keys are left alone, so an application may keep its own.
    private def check_section_names!(content : String) : Nil
      list_of_top_level_keys = YAML.parse(content).as_h?.try(&.keys.map(&.to_s)) || [] of String
      list_of_known_names = Amber::Configuration::AppConfig.list_of_section_names +
                            Amber::Configuration.custom_config_defaults.keys
      list_of_errors = [] of String
      list_of_top_level_keys.each do |key|
        next if list_of_known_names.includes?(key)

        if intended_name = Levenshtein.find(key, list_of_known_names, tolerance: 2)
          list_of_errors << "unknown settings section `#{key}`; did you mean `#{intended_name}`?"
        end
      end
      raise Amber::Exceptions::ConfigurationError.new(list_of_errors) unless list_of_errors.empty?
    end

    private def load_v2_settings(content : String) : Settings
      check_section_names!(content)
      app_config = Amber::Configuration::AppConfig.from_yaml(content)

      # Load any registered custom configs from the YAML first, so the
      # environment variable pass reaches them as well as built-in sections.
      load_custom_configs(content, app_config)

      # Apply environment variable overrides
      Amber::Configuration::EnvOverride.apply_all(app_config)

      # Reject unusable parameter limits at boot rather than on the first request.
      app_config.params.validate!

      # Reject a security header value with a line break while the settings
      # load, so a bad value fails the boot instead of every response.
      app_config.security_headers.validate!

      # Build a Settings instance backed by the AppConfig
      settings = build_settings_from_app_config(app_config)
      settings
    end

    # Stores each registered custom section in the AppConfig as raw YAML:
    # the section's mapping from the environment file, or the values read
    # for a credentials section. A section with neither stays absent, and
    # `AppConfig#custom` returns its registered default.
    private def load_custom_configs(content : String, app_config : Amber::Configuration::AppConfig)
      parsed = YAML.parse(content)
      Amber::Configuration.custom_config_defaults.each_key do |key|
        yaml_node = parsed[key]?
        if credential_yaml = Amber::Configuration.credential_source(key)
          if yaml_node
            # Credentials come from the credentials directory only; a YAML
            # copy would either be ignored or replace them silently.
            raise Amber::Exceptions::ConfigurationError.new(
              "#{key} is loaded from the credentials directory; remove the #{key} section from #{yml_settings_file}"
            )
          end
          app_config.custom_configs[key] = credential_yaml
        elsif yaml_node
          app_config.custom_configs[key] = yaml_node.to_yaml
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
