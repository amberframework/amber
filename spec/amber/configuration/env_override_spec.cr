require "../../spec_helper"

# Helper to temporarily set env vars and clean up afterward.
private def with_env(vars : Hash(String, String), &)
  vars.each { |k, v| ENV[k] = v }
  begin
    yield
  ensure
    vars.each_key { |k| ENV.delete(k) }
  end
end

module Amber::Configuration
  describe EnvOverride do
    describe ".apply_all" do
      it "overrides security_headers.frame_options from AMBER_SECURITY_HEADERS_FRAME_OPTIONS" do
        with_env({"AMBER_SECURITY_HEADERS_FRAME_OPTIONS" => "SAMEORIGIN"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.security_headers.frame_options.should eq "SAMEORIGIN"
        end
      end

      it "overrides every security_headers key from its AMBER_SECURITY_HEADERS_ variable" do
        with_env({
          "AMBER_SECURITY_HEADERS_CONTENT_TYPE_OPTIONS"       => "nosniff-test",
          "AMBER_SECURITY_HEADERS_CONTENT_SECURITY_POLICY"    => "frame-ancestors 'self'",
          "AMBER_SECURITY_HEADERS_REFERRER_POLICY"            => "no-referrer",
          "AMBER_SECURITY_HEADERS_PERMISSIONS_POLICY"         => "camera=(self)",
          "AMBER_SECURITY_HEADERS_CROSS_ORIGIN_OPENER_POLICY" => "same-origin-allow-popups",
          "AMBER_SECURITY_HEADERS_STRICT_TRANSPORT_SECURITY"  => "max-age=600",
        }) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          security_headers = config.security_headers
          security_headers.content_type_options.should eq "nosniff-test"
          security_headers.content_security_policy.should eq "frame-ancestors 'self'"
          security_headers.referrer_policy.should eq "no-referrer"
          security_headers.permissions_policy.should eq "camera=(self)"
          security_headers.cross_origin_opener_policy.should eq "same-origin-allow-popups"
          security_headers.strict_transport_security.should eq "max-age=600"
        end
      end

      it "turns a security header off with an empty AMBER_SECURITY_HEADERS_ value" do
        with_env({"AMBER_SECURITY_HEADERS_STRICT_TRANSPORT_SECURITY" => ""}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.security_headers.sends_strict_transport_security?.should be_false
        end
      end

      it "overrides server.host from AMBER_SERVER_HOST" do
        with_env({"AMBER_SERVER_HOST" => "0.0.0.0"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.host.should eq "0.0.0.0"
        end
      end

      it "overrides server.port from AMBER_SERVER_PORT" do
        with_env({"AMBER_SERVER_PORT" => "8080"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.port.should eq 8080
        end
      end

      it "overrides server.port_reuse from AMBER_SERVER_PORT_REUSE" do
        with_env({"AMBER_SERVER_PORT_REUSE" => "false"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.port_reuse.should be_false
        end
      end

      it "overrides server.process_count from AMBER_SERVER_PROCESS_COUNT" do
        with_env({"AMBER_SERVER_PROCESS_COUNT" => "4"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.process_count.should eq 4
        end
      end

      it "overrides server.secret_key_base from AMBER_SERVER_SECRET_KEY_BASE" do
        with_env({"AMBER_SERVER_SECRET_KEY_BASE" => "env-secret"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.secret_key_base.should eq "env-secret"
        end
      end

      it "overrides database.url from AMBER_DATABASE_URL" do
        with_env({"AMBER_DATABASE_URL" => "postgres://prod:5432/db"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.database.url.should eq "postgres://prod:5432/db"
        end
      end

      it "supports the ecosystem-standard DATABASE_URL" do
        with_env({"DATABASE_URL" => "postgres://platform:5432/app"}) do
          config = AppConfig.new
          result = EnvOverride.apply_all(config)
          result.database.url.should eq("postgres://platform:5432/app")
        end
      end

      it "prefers AMBER_DATABASE_URL when both database variables are set" do
        with_env({
          "DATABASE_URL"       => "postgres://platform:5432/app",
          "AMBER_DATABASE_URL" => "postgres://amber:5432/app",
        }) do
          config = AppConfig.new
          result = EnvOverride.apply_all(config)
          result.database.url.should eq("postgres://amber:5432/app")
        end
      end

      it "overrides session.store from AMBER_SESSION_STORE" do
        with_env({"AMBER_SESSION_STORE" => "encrypted_cookie"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.session.store.should eq "encrypted_cookie"
        end
      end

      it "overrides logging.severity from AMBER_LOGGING_SEVERITY" do
        with_env({"AMBER_LOGGING_SEVERITY" => "error"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.logging.severity.should eq "error"
        end
      end

      it "overrides logging.colorize from AMBER_LOGGING_COLORIZE" do
        with_env({"AMBER_LOGGING_COLORIZE" => "false"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.logging.colorize.should be_false
        end
      end

      it "overrides jobs.workers from AMBER_JOBS_WORKERS" do
        with_env({"AMBER_JOBS_WORKERS" => "8"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.jobs.workers.should eq 8
        end
      end

      it "overrides jobs.auto_start from AMBER_JOBS_AUTO_START" do
        with_env({"AMBER_JOBS_AUTO_START" => "true"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.jobs.auto_start.should be_true
        end
      end

      it "overrides jobs.polling_interval_seconds from env var" do
        with_env({"AMBER_JOBS_POLLING_INTERVAL_SECONDS" => "2.5"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.jobs.polling_interval_seconds.should eq 2.5
        end
      end

      it "overrides mailer.adapter from AMBER_MAILER_ADAPTER" do
        with_env({"AMBER_MAILER_ADAPTER" => "smtp"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.mailer.adapter.should eq "smtp"
        end
      end

      it "overrides mailer.smtp.host from AMBER_MAILER_SMTP_HOST" do
        with_env({"AMBER_MAILER_SMTP_HOST" => "smtp.gmail.com"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.mailer.smtp.host.should eq "smtp.gmail.com"
        end
      end

      it "overrides mailer.smtp.port from AMBER_MAILER_SMTP_PORT" do
        with_env({"AMBER_MAILER_SMTP_PORT" => "465"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.mailer.smtp.port.should eq 465
        end
      end

      it "overrides mailer.smtp.use_tls from AMBER_MAILER_SMTP_USE_TLS" do
        with_env({"AMBER_MAILER_SMTP_USE_TLS" => "false"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.mailer.smtp.use_tls.should be_false
        end
      end

      it "overrides pubsub.adapter from AMBER_PUBSUB_ADAPTER" do
        with_env({"AMBER_PUBSUB_ADAPTER" => "redis"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.pubsub.adapter.should eq "redis"
        end
      end

      it "overrides app name from AMBER_NAME" do
        with_env({"AMBER_NAME" => "overridden_app"}) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.name.should eq "overridden_app"
        end
      end

      it "does not override when env var is not set" do
        # Make sure no AMBER_SERVER_HOST is set
        ENV.delete("AMBER_SERVER_HOST")

        config = AppConfig.new
        config.server.host = "original_host"
        EnvOverride.apply_all(config)
        config.server.host.should eq "original_host"
      end

      it "handles boolean parsing for various true values" do
        ["true", "1", "yes", "TRUE", "Yes"].each do |true_val|
          with_env({"AMBER_JOBS_AUTO_START" => true_val}) do
            config = AppConfig.new
            EnvOverride.apply_all(config)
            config.jobs.auto_start.should be_true
          end
        end
      end

      it "handles boolean parsing for false values" do
        ["false", "0", "no", "anything"].each do |false_val|
          with_env({"AMBER_JOBS_AUTO_START" => false_val}) do
            config = AppConfig.new
            EnvOverride.apply_all(config)
            config.jobs.auto_start.should be_false
          end
        end
      end

      it "applies multiple overrides at once" do
        vars = {
          "AMBER_SERVER_HOST"    => "0.0.0.0",
          "AMBER_SERVER_PORT"    => "8080",
          "AMBER_DATABASE_URL"   => "postgres://prod/db",
          "AMBER_JOBS_WORKERS"   => "16",
          "AMBER_MAILER_ADAPTER" => "smtp",
        }
        with_env(vars) do
          config = AppConfig.new
          EnvOverride.apply_all(config)
          config.server.host.should eq "0.0.0.0"
          config.server.port.should eq 8080
          config.database.url.should eq "postgres://prod/db"
          config.jobs.workers.should eq 16
          config.mailer.adapter.should eq "smtp"
        end
      end
    end
  end
end
