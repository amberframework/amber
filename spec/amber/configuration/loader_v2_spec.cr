require "../../spec_helper"

# A YAML::Serializable type whose field has no YAML constructor, like a Grant
# model with a UUID column. Nothing deserializes it, so the program compiles
# only if Amber does not call `from_yaml` through the union of every
# YAML::Serializable type when it loads custom config sections.
class LoaderValueWithoutYamlConstructor
end

class LoaderRecordWithoutYamlColumns
  include YAML::Serializable

  property value : LoaderValueWithoutYamlConstructor = LoaderValueWithoutYamlConstructor.new

  def initialize
  end
end

class LoaderCustomConfig
  include YAML::Serializable

  property api_key : String = ""
  property timeout : Int32 = 30

  def initialize
  end
end

module Amber::Environment
  describe Loader do
    Dir.cd CURRENT_DIR

    describe "#detect_format" do
      it "detects V1 flat format" do
        v1_content = File.read(File.expand_path("./spec/support/config/test.yml"))
        loader = Loader.new(:test, "./spec/support/config/")
        loader.detect_format(v1_content).should eq :v1
      end

      it "detects V2 nested format" do
        v2_content = File.read(File.expand_path("./spec/support/config/v2_test.yml"))
        loader = Loader.new(:test, "./spec/support/config/")
        loader.detect_format(v2_content).should eq :v2
      end
    end

    describe "V2 YAML loading" do
      it "loads a V2 YAML file and returns a Settings instance" do
        loader = Loader.new(:v2_test, "./spec/support/config/")
        settings = loader.settings
        settings.should be_a Amber::Environment::Settings
      end

      it "populates V1 properties from V2 YAML" do
        loader = Loader.new(:v2_test, "./spec/support/config/")
        settings = loader.settings

        settings.name.should eq "v2_test_app"
        settings.host.should eq "0.0.0.0"
        settings.port.should eq 3001
        settings.port_reuse.should be_true
        settings.process_count.should eq 2
        settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
        settings.database_url.should eq "postgres://localhost:5432/v2_test_db"
        settings.ssl_key_file.should be_nil
        settings.ssl_cert_file.should be_nil
      end

      it "provides V2 subsection accessors from V2 YAML" do
        loader = Loader.new(:v2_test, "./spec/support/config/")
        settings = loader.settings

        settings.server.host.should eq "0.0.0.0"
        settings.server.port.should eq 3001
        settings.server.process_count.should eq 2

        settings.database.url.should eq "postgres://localhost:5432/v2_test_db"

        settings.mailer.adapter.should eq "smtp"
        settings.mailer.default_from.should eq "test@example.com"
        settings.mailer.smtp.host.should eq "smtp.example.com"

        settings.static.headers.should eq({"Cache-Control" => "no-store"})
      end

      it "provides backward-compatible session hash from V2 YAML" do
        loader = Loader.new(:v2_test, "./spec/support/config/")
        settings = loader.settings

        settings.session[:key].should eq "v2_test.session"
        settings.session[:store].should eq :signed_cookie
        settings.session[:expires].should eq 120
        settings.session[:adapter].should eq "memory"
      end

      it "provides backward-compatible pubsub hash from V2 YAML" do
        loader = Loader.new(:v2_test, "./spec/support/config/")
        settings = loader.settings

        settings.pubsub[:adapter].should eq "memory"
      end

      it "loads a minimal V2 YAML with defaults" do
        loader = Loader.new(:v2_minimal, "./spec/support/config/")
        settings = loader.settings

        settings.name.should eq "v2_minimal_app"
        settings.host.should eq "localhost"
        settings.port.should eq 3000

        # Defaults should be preserved
        settings.session[:key].should eq "amber.session"
        settings.session[:store].should eq :signed_cookie
        settings.pubsub[:adapter].should eq "memory"
      end

      it "loads custom config sections lazily by concrete type" do
        Amber::Configuration.register_custom("spec_loader_custom", LoaderCustomConfig.new)
        dir = File.tempname("amber-loader-custom")
        config_path = File.join(dir, "custom_loader.yml")
        Dir.mkdir_p(dir)
        File.write(config_path, <<-YAML)
        name: custom_loader_app
        server:
          secret_key_base: "agentc-placeholder:local-dev-only-at-least-32-chars"
        spec_loader_custom:
          api_key: "agentc-placeholder:loader-key"
          timeout: 75
        YAML

        loader = Loader.new(:custom_loader, dir)
        settings = loader.settings

        custom = settings.custom(:spec_loader_custom, LoaderCustomConfig)
        custom.api_key.should eq "agentc-placeholder:loader-key"
        custom.timeout.should eq 75
      ensure
        File.delete(config_path) if config_path && File.exists?(config_path)
        Dir.delete(dir) if dir && Dir.exists?(dir)
      end
    end

    describe "V1 YAML backward compatibility" do
      it "rejects AMBER_SERVER_UNIX_SOCKET with a V1 file instead of serving on TCP" do
        ENV["AMBER_SERVER_UNIX_SOCKET"] = "/run/app/app.sock"
        begin
          expect_raises(Amber::Exceptions::ConfigurationError, /server.unix_socket needs the V2 settings format/) do
            Loader.new(:test, "./spec/support/config/").settings
          end
        ensure
          ENV.delete("AMBER_SERVER_UNIX_SOCKET")
        end
      end

      it "still loads V1 format YAML files correctly" do
        loader = Loader.new(:test, "./spec/support/config/")
        settings = loader.settings

        settings.name.should eq "test_settings"
        settings.host.should eq "0.0.0.0"
        settings.port.should eq 3000
        settings.database_url.should eq "mysql://root@localhost:3306/test_settings_test"
      end

      it "provides V2 subsection accessors from V1 YAML via conversion" do
        loader = Loader.new(:test, "./spec/support/config/")
        settings = loader.settings

        settings.server.host.should eq "0.0.0.0"
        settings.server.port.should eq 3000
        settings.database.url.should eq "mysql://root@localhost:3306/test_settings_test"
      end
    end

    describe "environment variable overrides on V2 format" do
      it "applies env var overrides to V2 loaded config" do
        ENV["AMBER_SERVER_PORT"] = "9999"
        begin
          loader = Loader.new(:v2_test, "./spec/support/config/")
          settings = loader.settings

          settings.port.should eq 9999
          settings.server.port.should eq 9999
        ensure
          ENV.delete("AMBER_SERVER_PORT")
        end
      end

      it "applies env var overrides to nested config" do
        ENV["AMBER_MAILER_SMTP_HOST"] = "env-smtp.example.com"
        begin
          loader = Loader.new(:v2_test, "./spec/support/config/")
          settings = loader.settings

          settings.mailer.smtp.host.should eq "env-smtp.example.com"
        ensure
          ENV.delete("AMBER_MAILER_SMTP_HOST")
        end
      end
    end
  end
end
