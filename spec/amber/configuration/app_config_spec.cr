require "../../spec_helper"

module Amber::Configuration
  describe AppConfig do
    Dir.cd CURRENT_DIR

    describe "defaults" do
      it "has sensible default values for all sections" do
        config = AppConfig.new
        config.name.should eq "Amber_App"
        config.server.host.should eq "localhost"
        config.server.port.should eq 3000
        config.database.url.should eq ""
        config.session.key.should eq "amber.session"
        config.pubsub.adapter.should eq "memory"
        config.logging.severity.should eq "debug"
        config.jobs.workers.should eq 1
        config.mailer.adapter.should eq "memory"
        config.static.headers.should eq({} of String => String)
        config.secrets.should eq({} of String => String)
      end
    end

    describe "YAML deserialization" do
      it "deserializes a full V2 YAML configuration" do
        yaml_content = File.read(File.expand_path("./spec/support/config/v2_test.yml"))
        config = AppConfig.from_yaml(yaml_content)

        config.name.should eq "v2_test_app"
        config.server.host.should eq "0.0.0.0"
        config.server.port.should eq 3001
        config.server.port_reuse.should be_true
        config.server.process_count.should eq 2
        config.server.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
        config.server.ssl.key_file.should be_nil
        config.server.ssl.cert_file.should be_nil

        config.database.url.should eq "postgres://localhost:5432/v2_test_db"

        config.session.key.should eq "v2_test.session"
        config.session.store.should eq "signed_cookie"
        config.session.expires.should eq 120
        config.session.adapter.should eq "memory"

        config.pubsub.adapter.should eq "memory"

        config.logging.severity.should eq "warn"
        config.logging.colorize.should be_true
        config.logging.filter.should eq ["password", "confirm_password"]

        config.jobs.adapter.should eq "memory"
        config.jobs.queues.should eq ["default", "critical"]
        config.jobs.workers.should eq 2
        config.jobs.auto_start.should be_false

        config.mailer.adapter.should eq "smtp"
        config.mailer.default_from.should eq "test@example.com"
        config.mailer.smtp.host.should eq "smtp.example.com"
        config.mailer.smtp.port.should eq 587

        config.static.headers.should eq({"Cache-Control" => "no-store"})

        config.secrets["description"].should eq "V2 test secrets"
        config.secrets["api_key"].should eq "test-key-123"
      end

      it "deserializes a minimal V2 YAML with defaults for omitted sections" do
        yaml_content = File.read(File.expand_path("./spec/support/config/v2_minimal.yml"))
        config = AppConfig.from_yaml(yaml_content)

        config.name.should eq "v2_minimal_app"
        config.server.host.should eq "localhost"
        config.server.port.should eq 3000

        # Defaults should be used for omitted sections
        config.database.url.should eq ""
        config.session.key.should eq "amber.session"
        config.logging.severity.should eq "debug"
        config.jobs.workers.should eq 1
        config.mailer.adapter.should eq "memory"
      end
    end

    describe "#validate!" do
      it "passes validation with a valid configuration" do
        config = AppConfig.new
        config.server.secret_key_base = "a-very-long-secret-key-that-is-at-least-32-chars"
        config.validate! # should not raise
      end

      it "collects multiple validation errors" do
        config = AppConfig.new
        config.server.port = 0
        config.server.secret_key_base = "short"
        config.logging.severity = "invalid"

        expect_raises(Amber::Exceptions::ConfigurationError) do
          config.validate!
        end
      end

      it "includes errors from multiple sections in the error message" do
        config = AppConfig.new
        config.server.port = 0
        config.logging.severity = "invalid"

        begin
          config.validate!
          fail "Expected ConfigurationError to be raised"
        rescue ex : Amber::Exceptions::ConfigurationError
          ex.list_of_errors.size.should be >= 2
          ex.list_of_errors.any? { |e| e.includes?("server.port") }.should be_true
          ex.list_of_errors.any? { |e| e.includes?("logging.severity") }.should be_true
        end
      end
    end

    describe "#custom" do
      it "retrieves a registered custom config" do
        config = AppConfig.new
        custom_instance = TestCustomConfig.new
        custom_instance.test_value = "custom_value"
        config.custom_configs["test_custom"] = custom_instance

        retrieved = config.custom(:test_custom, TestCustomConfig)
        retrieved.test_value.should eq "custom_value"
      end
    end
  end
end

# Test custom config struct defined outside the describe block for use in custom config specs
class TestCustomConfig
  include YAML::Serializable

  property test_value : String = "default"
  property test_number : Int32 = 42

  def initialize
  end
end
