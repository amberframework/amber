module Amber::Configuration
  module EnvOverride
    # Apply environment variable overrides to an AppConfig instance,
    # checking for AMBER_{SECTION}_{KEY} environment variables for each
    # property in each subsection.
    #
    # Environment variables always take highest priority, overriding
    # both YAML file values and compiled-in defaults.
    def self.apply_all(config : AppConfig) : AppConfig
      # Top-level
      if env_val = ENV["AMBER_NAME"]?
        config.name = env_val
      end

      # Server section
      apply_server(config.server)

      # Server SSL sub-section
      apply_server_ssl(config.server.ssl)

      # Database section
      apply_database(config.database)

      # Session section
      apply_session(config.session)

      # PubSub section
      apply_pubsub(config.pubsub)

      # Logging section
      apply_logging(config.logging)

      # Jobs section
      apply_jobs(config.jobs)

      # Mailer section
      apply_mailer(config.mailer)

      # Mailer SMTP sub-section
      apply_mailer_smtp(config.mailer.smtp)

      # Registered custom sections, including credentials sections
      apply_custom(config)

      config
    end

    # Apply `AMBER_{SECTION}_{KEY}` overrides to every registered custom
    # section loaded into *config*, the same way the built-in sections are
    # overridden. Nested mappings extend the name, as with
    # `AMBER_SERVER_SSL_KEY_FILE`: `AMBER_{SECTION}_{SUBSECTION}_{KEY}`.
    #
    # Section and key names are upper-cased, and any character other than a
    # letter or digit becomes `_`. Values are read as plain YAML scalars, so
    # `8080` fills an `Int32` field and `true` fills a `Bool`.
    #
    # Raises `Amber::Exceptions::ConfigurationError` naming the variable when
    # its value does not fit the field's type. The value itself is left out
    # of the message because it may be a secret.
    def self.apply_custom(config : AppConfig) : Nil
      config.custom_configs.keys.each do |section|
        list_of_keys = Amber::Configuration.custom_config_keys(section)
        next unless list_of_keys

        document = YAML::Nodes.parse(config.custom_configs[section].to_yaml)
        mapping = document.nodes.first?
        next unless mapping.is_a?(YAML::Nodes::Mapping)

        list_of_applied_variables = [] of String
        apply_to_mapping(mapping, "AMBER_#{env_name(section)}", list_of_keys, list_of_applied_variables)
        next if list_of_applied_variables.empty?

        begin
          if rebuilt_section = Amber::Configuration.build_custom_from_node(section, mapping)
            config.custom_configs[section] = rebuilt_section
          end
        rescue YAML::ParseException
          raise Amber::Exceptions::ConfigurationError.new(
            "#{list_of_applied_variables.join(", ")}: value does not fit the field type in the #{section} section"
          )
        end
      end
    end

    # Overwrites or adds each key of *mapping* that has a matching
    # environment variable, then recurses into nested mappings.
    private def self.apply_to_mapping(mapping : YAML::Nodes::Mapping, prefix : String,
                                      list_of_keys : Array(String), list_of_applied_variables : Array(String)) : Nil
      list_of_keys.each do |key|
        variable = "#{prefix}_#{env_name(key)}"
        value_index = index_of_value(mapping, key)
        existing_value = value_index ? mapping.nodes[value_index] : nil

        if existing_value.is_a?(YAML::Nodes::Mapping)
          apply_to_mapping(existing_value, variable, scalar_keys_of(existing_value), list_of_applied_variables)
        elsif override = ENV[variable]?
          override_node = YAML::Nodes::Scalar.new(override)
          override_node.style = YAML::ScalarStyle::PLAIN
          if value_index
            mapping.nodes[value_index] = override_node
          else
            mapping[YAML::Nodes::Scalar.new(key)] = override_node
          end
          list_of_applied_variables << variable
        end
      end
    end

    private def self.index_of_value(mapping : YAML::Nodes::Mapping, key : String) : Int32?
      mapping.nodes.each_slice(2).with_index do |(key_node, _value_node), pair_index|
        if key_node.is_a?(YAML::Nodes::Scalar) && key_node.value == key
          return pair_index * 2 + 1
        end
      end
      nil
    end

    private def self.scalar_keys_of(mapping : YAML::Nodes::Mapping) : Array(String)
      list_of_keys = [] of String
      mapping.nodes.each_slice(2) do |(key_node, _value_node)|
        list_of_keys << key_node.value if key_node.is_a?(YAML::Nodes::Scalar)
      end
      list_of_keys
    end

    private def self.env_name(name : String) : String
      name.upcase.gsub(/[^A-Z0-9]/, "_")
    end

    private def self.apply_server(config : ServerConfig) : Nil
      if v = ENV["AMBER_SERVER_HOST"]?
        config.host = v
      end
      if v = ENV["AMBER_SERVER_PORT"]?
        config.port = v.to_i
      end
      if v = ENV["AMBER_SERVER_PORT_REUSE"]?
        config.port_reuse = parse_bool(v)
      end
      if v = ENV["AMBER_SERVER_PROCESS_COUNT"]?
        config.process_count = v.to_i
      end
      if v = ENV["AMBER_SERVER_SECRET_KEY_BASE"]?
        config.secret_key_base = v
      end
    end

    private def self.apply_server_ssl(config : SSLConfig) : Nil
      if v = ENV["AMBER_SERVER_SSL_KEY_FILE"]?
        config.key_file = v
      end
      if v = ENV["AMBER_SERVER_SSL_CERT_FILE"]?
        config.cert_file = v
      end
    end

    private def self.apply_database(config : DatabaseConfig) : Nil
      if v = ENV["AMBER_DATABASE_URL"]?
        config.url = v
      elsif v = ENV["DATABASE_URL"]?
        # DATABASE_URL is the ecosystem convention used by Grant, Micrate,
        # managed databases, and the generated Amber V2 application. Keep the
        # Amber-prefixed form as the explicit higher-priority override.
        config.url = v
      end
    end

    private def self.apply_session(config : SessionConfig) : Nil
      if v = ENV["AMBER_SESSION_KEY"]?
        config.key = v
      end
      if v = ENV["AMBER_SESSION_STORE"]?
        config.store = v
      end
      if v = ENV["AMBER_SESSION_EXPIRES"]?
        config.expires = v.to_i
      end
      if v = ENV["AMBER_SESSION_ADAPTER"]?
        config.adapter = v
      end
    end

    private def self.apply_pubsub(config : PubSubConfig) : Nil
      if v = ENV["AMBER_PUBSUB_ADAPTER"]?
        config.adapter = v
      end
    end

    private def self.apply_logging(config : LoggingConfig) : Nil
      if v = ENV["AMBER_LOGGING_SEVERITY"]?
        config.severity = v
      end
      if v = ENV["AMBER_LOGGING_COLORIZE"]?
        config.colorize = parse_bool(v)
      end
      if v = ENV["AMBER_LOGGING_COLOR"]?
        config.color = v
      end
    end

    private def self.apply_jobs(config : JobsConfig) : Nil
      if v = ENV["AMBER_JOBS_ADAPTER"]?
        config.adapter = v
      end
      if v = ENV["AMBER_JOBS_WORKERS"]?
        config.workers = v.to_i
      end
      if v = ENV["AMBER_JOBS_WORK_STEALING"]?
        config.work_stealing = parse_bool(v)
      end
      if v = ENV["AMBER_JOBS_POLLING_INTERVAL_SECONDS"]?
        config.polling_interval_seconds = v.to_f
      end
      if v = ENV["AMBER_JOBS_SCHEDULER_INTERVAL_SECONDS"]?
        config.scheduler_interval_seconds = v.to_f
      end
      if v = ENV["AMBER_JOBS_AUTO_START"]?
        config.auto_start = parse_bool(v)
      end
    end

    private def self.apply_mailer(config : MailerConfig) : Nil
      if v = ENV["AMBER_MAILER_ADAPTER"]?
        config.adapter = v
      end
      if v = ENV["AMBER_MAILER_DEFAULT_FROM"]?
        config.default_from = v
      end
    end

    private def self.apply_mailer_smtp(config : SMTPConfig) : Nil
      if v = ENV["AMBER_MAILER_SMTP_HOST"]?
        config.host = v
      end
      if v = ENV["AMBER_MAILER_SMTP_PORT"]?
        config.port = v.to_i
      end
      if v = ENV["AMBER_MAILER_SMTP_USERNAME"]?
        config.username = v
      end
      if v = ENV["AMBER_MAILER_SMTP_PASSWORD"]?
        config.password = v
      end
      if v = ENV["AMBER_MAILER_SMTP_USE_TLS"]?
        config.use_tls = parse_bool(v)
      end
      if v = ENV["AMBER_MAILER_SMTP_HELO_DOMAIN"]?
        config.helo_domain = v
      end
    end

    # Parse a string value as a boolean.
    # Accepts "true", "1", "yes" (case-insensitive) as true; everything else is false.
    private def self.parse_bool(value : String) : Bool
      value.downcase.in?("true", "1", "yes")
    end
  end
end
