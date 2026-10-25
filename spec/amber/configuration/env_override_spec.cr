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

struct SpecOverrideSmtpConfig
  include YAML::Serializable

  property host : String = "localhost"
  property port : Int32 = 25

  def initialize
  end
end

struct SpecOverrideConfig
  include YAML::Serializable

  property api_key : String = "agentc-placeholder:spec-default-key"
  property timeout : Int32 = 30
  property? enabled : Bool = false
  property webhook_secret : String? = nil

  @[YAML::Field(key: "base-url")]
  property base_url : String = "https://example.com"

  property smtp : SpecOverrideSmtpConfig = SpecOverrideSmtpConfig.new

  # Absent from the serialized section until something sets it.
  property relay : SpecOverrideSmtpConfig? = nil

  property interval_seconds : Float64 = 1.5

  # Read from YAML but never written back out.
  @[YAML::Field(ignore_serialize: true)]
  property signing_secret : String = "agentc-placeholder:spec-default-signing-secret"

  def initialize
  end
end

# Builds an AppConfig holding a registered custom section, the way the
# loader does before it runs the override pass.
private def app_config_with_custom_section(section : String) : Amber::Configuration::AppConfig
  Amber::Configuration.register_custom(section, SpecOverrideConfig.new)
  config = Amber::Configuration::AppConfig.new
  config.custom_configs[section] = Amber::Configuration.custom_config_defaults[section]
  config
end

module Amber::Configuration
  describe EnvOverride do
    describe ".apply_all" do
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

      context "with a registered custom section" do
        it "overrides a String field from AMBER_{SECTION}_{KEY}" do
          with_env({"AMBER_SPEC_OVERRIDE_API_KEY" => "agentc-placeholder:spec-env-key"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            config.custom(:spec_override, SpecOverrideConfig).api_key.should eq "agentc-placeholder:spec-env-key"
          end
        end

        it "converts Int32 and Bool fields from their plain text" do
          vars = {"AMBER_SPEC_OVERRIDE_TIMEOUT" => "90", "AMBER_SPEC_OVERRIDE_ENABLED" => "true"}
          with_env(vars) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            section = config.custom(:spec_override, SpecOverrideConfig)
            section.timeout.should eq 90
            section.enabled?.should be_true
          end
        end

        it "reaches a nilable field whose value is nil" do
          with_env({"AMBER_SPEC_OVERRIDE_WEBHOOK_SECRET" => "agentc-placeholder:spec-webhook-secret"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            config.custom(:spec_override, SpecOverrideConfig).webhook_secret.should eq "agentc-placeholder:spec-webhook-secret"
          end
        end

        it "names the variable after the YAML key, with other characters as underscores" do
          with_env({"AMBER_SPEC_OVERRIDE_BASE_URL" => "https://env.example.com"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            config.custom(:spec_override, SpecOverrideConfig).base_url.should eq "https://env.example.com"
          end
        end

        it "overrides a nested section from AMBER_{SECTION}_{SUBSECTION}_{KEY}" do
          with_env({"AMBER_SPEC_OVERRIDE_SMTP_PORT" => "587"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            section = config.custom(:spec_override, SpecOverrideConfig)
            section.smtp.port.should eq 587
            section.smtp.host.should eq "localhost"
          end
        end

        it "keeps values from YAML when no variable is set" do
          Amber::Configuration.register_custom("spec_override_yaml", SpecOverrideConfig.new)
          config = AppConfig.new
          config.custom_configs["spec_override_yaml"] = SpecOverrideConfig.from_yaml("api_key: yaml-key\ntimeout: 45")
          EnvOverride.apply_all(config)
          section = config.custom(:spec_override_yaml, SpecOverrideConfig)
          section.api_key.should eq "yaml-key"
          section.timeout.should eq 45
        end

        it "raises a ConfigurationError naming the variable, not the value, on a type mismatch" do
          with_env({"AMBER_SPEC_OVERRIDE_TIMEOUT" => "not-a-number-secret"}) do
            config = app_config_with_custom_section("spec_override")
            error = expect_raises(Amber::Exceptions::ConfigurationError, /AMBER_SPEC_OVERRIDE_TIMEOUT/) do
              EnvOverride.apply_all(config)
            end
            error.message.to_s.should_not contain "not-a-number-secret"
          end
        end

        it "keeps an empty String override as empty text, not nil" do
          with_env({"AMBER_SPEC_OVERRIDE_WEBHOOK_SECRET" => "", "AMBER_SPEC_OVERRIDE_API_KEY" => "null"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            section = config.custom(:spec_override, SpecOverrideConfig)
            section.webhook_secret.should eq ""
            section.api_key.should eq "null"
          end
        end

        it "reads Bool and Float fields the way the built-in pass does" do
          vars = {"AMBER_SPEC_OVERRIDE_ENABLED" => "1", "AMBER_SPEC_OVERRIDE_INTERVAL_SECONDS" => "2"}
          with_env(vars) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            section = config.custom(:spec_override, SpecOverrideConfig)
            section.enabled?.should be_true
            section.interval_seconds.should eq 2.0
          end
        end

        it "raises a ConfigurationError naming the variable for a Float field that is not a number" do
          with_env({"AMBER_SPEC_OVERRIDE_INTERVAL_SECONDS" => "agentc-placeholder:not-a-number"}) do
            config = app_config_with_custom_section("spec_override")
            error = expect_raises(Amber::Exceptions::ConfigurationError, /AMBER_SPEC_OVERRIDE_INTERVAL_SECONDS/) do
              EnvOverride.apply_all(config)
            end
            error.message.to_s.should_not contain "not-a-number"
          end
        end

        it "creates a nested section that is nil to hold its override" do
          with_env({"AMBER_SPEC_OVERRIDE_RELAY_HOST" => "relay.example.com"}) do
            config = app_config_with_custom_section("spec_override")
            config.custom(:spec_override, SpecOverrideConfig).relay.should be_nil
            EnvOverride.apply_all(config)
            relay = config.custom(:spec_override, SpecOverrideConfig).relay
            relay.should_not be_nil
            if relay
              relay.host.should eq "relay.example.com"
              relay.port.should eq 25
            end
          end
        end

        it "leaves a nil nested section nil when none of its variables is set" do
          with_env({"AMBER_SPEC_OVERRIDE_TIMEOUT" => "15"}) do
            config = app_config_with_custom_section("spec_override")
            EnvOverride.apply_all(config)
            config.custom(:spec_override, SpecOverrideConfig).relay.should be_nil
          end
        end

        it "keeps a field the type does not serialize when another field is overridden" do
          Amber::Configuration.register_custom("spec_override_sourced", SpecOverrideConfig.new)
          with_env({"AMBER_SPEC_OVERRIDE_SOURCED_TIMEOUT" => "75"}) do
            settings = Amber::Environment::Loader.new(:v2_with_custom_section, "./spec/support/config/").settings
            section = settings.custom(:spec_override_sourced, SpecOverrideConfig)
            section.timeout.should eq 75
            section.api_key.should eq "agentc-placeholder:spec-yaml-key"
            section.signing_secret.should eq "agentc-placeholder:spec-yaml-signing-secret"
          end
        end

        it "reaches a section loaded from YAML by the loader" do
          Amber::Configuration.register_custom("spec_override_loaded", SpecOverrideConfig.new)
          with_env({"AMBER_SPEC_OVERRIDE_LOADED_API_KEY" => "agentc-placeholder:spec-loader-env-key"}) do
            settings = Amber::Environment::Loader.new(:v2_minimal, "./spec/support/config/").settings
            settings.custom(:spec_override_loaded, SpecOverrideConfig).api_key.should eq "agentc-placeholder:spec-loader-env-key"
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
