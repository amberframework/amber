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

      config
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
