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
    # overridden. Nested sections extend the name, as with
    # `AMBER_SERVER_SSL_KEY_FILE`: `AMBER_{SECTION}_{SUBSECTION}_{KEY}`,
    # and a nested section that is nil or absent is created to hold it.
    #
    # Section and key names are upper-cased, and any character other than a
    # letter or digit becomes `_`. Values follow the field's type, as in the
    # built-in pass: `String` fields keep the text as given (an empty value
    # stays empty), `Bool` fields accept `true`, `1` or `yes`, `Float` fields
    # accept any number, and other fields read the value as a plain YAML
    # scalar, so `8080` fills an `Int32`.
    #
    # The section is rebuilt from the YAML it was loaded from, or from the
    # credentials it was read from, with the overrides applied.
    #
    # Raises `Amber::Exceptions::ConfigurationError` naming the variable when
    # its value does not fit the field's type. The value itself is left out
    # of the message because it may be a secret.
    def self.apply_custom(config : AppConfig) : Nil
      config.custom_configs.keys.each do |section|
        list_of_fields = Amber::Configuration.custom_config_fields(section)
        next unless list_of_fields

        mapping = source_mapping(config, section)
        list_of_applied_variables = [] of String
        apply_to_mapping(mapping, "AMBER_#{env_name(section)}", list_of_fields, list_of_applied_variables)
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

    # Returns the mapping a section was loaded from, falling back to the
    # section's serialized form when the loader recorded no source.
    private def self.source_mapping(config : AppConfig, section : String) : YAML::Nodes::Mapping
      source = config.custom_config_sources[section]?
      source ||= YAML::Nodes.parse(config.custom_configs[section].to_yaml).nodes.first?
      source.as?(YAML::Nodes::Mapping) || YAML::Nodes::Mapping.new
    end

    # Overwrites or adds each field of *mapping* that has a matching
    # environment variable, then recurses into nested sections, creating a
    # nested mapping only when a variable inside it is set.
    private def self.apply_to_mapping(mapping : YAML::Nodes::Mapping, prefix : String,
                                      list_of_fields : Array(SectionField), list_of_applied_variables : Array(String)) : Nil
      list_of_fields.each do |field|
        variable = "#{prefix}_#{env_name(field.key)}"
        value_index = index_of_value(mapping, field.key)
        existing_value = value_index ? mapping.nodes[value_index] : nil

        if field.value_kind.section?
          nested_mapping = existing_value.as?(YAML::Nodes::Mapping)
          created_mapping = nested_mapping.nil?
          nested_mapping ||= YAML::Nodes::Mapping.new
          applied_before = list_of_applied_variables.size
          apply_to_mapping(nested_mapping, variable, field.list_of_fields, list_of_applied_variables)
          if created_mapping && list_of_applied_variables.size > applied_before
            set_value(mapping, field.key, value_index, nested_mapping)
          end
        elsif existing_value.is_a?(YAML::Nodes::Mapping)
          # A hash-typed field: each of its existing keys takes a variable.
          apply_to_mapping(existing_value, variable, untyped_fields_of(existing_value), list_of_applied_variables)
        elsif override = ENV[variable]?
          set_value(mapping, field.key, value_index, override_node(field.value_kind, variable, override))
          list_of_applied_variables << variable
        end
      end
    end

    # Turns an environment value into a scalar the field's type accepts.
    private def self.override_node(value_kind : SectionField::Kind, variable : String, value : String) : YAML::Nodes::Scalar
      if value_kind.text?
        # Quoted, so "", "null" and "true" stay that text in a String field.
        scalar(value, YAML::ScalarStyle::DOUBLE_QUOTED)
      elsif value_kind.flag?
        scalar(parse_bool(value).to_s, YAML::ScalarStyle::PLAIN)
      elsif value_kind.decimal?
        number = value.to_f?
        unless number
          raise Amber::Exceptions::ConfigurationError.new("#{variable}: value is not a number")
        end
        scalar(number.to_s, YAML::ScalarStyle::PLAIN)
      else
        scalar(value, YAML::ScalarStyle::PLAIN)
      end
    end

    private def self.scalar(value : String, style : YAML::ScalarStyle) : YAML::Nodes::Scalar
      node = YAML::Nodes::Scalar.new(value)
      node.style = style
      node
    end

    private def self.set_value(mapping : YAML::Nodes::Mapping, key : String, value_index : Int32?, value : YAML::Nodes::Node) : Nil
      if value_index
        mapping.nodes[value_index] = value
      else
        mapping[YAML::Nodes::Scalar.new(key)] = value
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

    private def self.untyped_fields_of(mapping : YAML::Nodes::Mapping) : Array(SectionField)
      list_of_fields = [] of SectionField
      mapping.nodes.each_slice(2) do |(key_node, _value_node)|
        if key_node.is_a?(YAML::Nodes::Scalar)
          list_of_fields << SectionField.new(key_node.value, SectionField::Kind::Other)
        end
      end
      list_of_fields
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
