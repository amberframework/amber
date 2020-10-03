require "../../spec_helper"

module Amber::Environment
  describe Settings do
    Dir.cd CURRENT_DIR

    it "loads default environment settings from yaml file" do
      test_yaml = File.read(File.expand_path("./spec/support/config/test.yml"))
      settings = Amber::Settings.from_yaml(test_yaml)

      settings.logging.severity.should eq Log::Severity::Warn
      settings.logging.colorize.should eq true
      settings.database_url.should eq "mysql://root@localhost:3306/test_settings_test"
      settings.host.should eq "0.0.0.0"
      settings.name.should eq "test_settings"
      settings.port.should eq 3000
      settings.port_reuse.should eq true
      settings.process_count.should eq 1
      settings.redis_url.should eq "redis://localhost:6379"
      settings.secret_key_base.should_not be_nil
      settings.secrets.should eq({"description" => "Store your test secrets credentials and settings here."})
      settings.secrets.is_a?(Hash(String, String)?).should be_true
      settings.session.should eq({
        :key => "amber.session", :store => :signed_cookie, :expires => 0,
      })
      settings.ssl_key_file.should be_nil
      settings.ssl_cert_file.should be_nil
    end

    it "loads logging color setting from yaml file" do
      color_yaml = File.read(File.expand_path("./spec/support/config/test_with_color.yml"))
      settings = Amber::Settings.from_yaml(color_yaml)
      settings.logging.color.should eq :red
    end

    describe "#static_file_server" do
      it "sets default headers value as empty map" do
        test_yaml = File.read(File.expand_path("./spec/support/config/development.yml"))
        settings = Amber::Settings.from_yaml(test_yaml)
        settings.pipes.dig?("static", "headers").should eq({} of String => Amber::Settings::SettingValue)
      end

      it "sets header file settings from environment yaml file" do
        test_yaml = File.read(File.expand_path("./spec/support/config/with_static_pipe_settings.yml"))
        settings = Amber::Settings.from_yaml(test_yaml)
        settings.pipes.dig?("static", "headers").should eq({"Cache-Control" => "private, max-age=7200"})
      end
    end
  end
end
