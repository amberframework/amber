require "../../spec_helper"

describe Amber::Server do
  describe ".configure" do
    it "it loads environment settings from test.yml" do
      settings = Amber::Server.settings

      settings.name.should eq "amber_test_app"
      settings.port_reuse.should eq true
      settings.redis_url.should eq "#{ENV["REDIS_URL"]? || "redis://localhost:6379"}"
      settings.port.should eq 3000
      settings.env.should eq "test"
      settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
      # Sometimes settings get over written by other tests first and this fails
      # expected_session = {:key => "amber.session", :store => "signed_cookie", :expires => "0"}
      # settings.session.should eq expected_session
      expected_secrets = {
        description: "Store your test secrets credentials and settings here.",
        database:    "mysql://root@localhost:3306/amber_test_app_test",
      }
      settings.secrets.should eq expected_secrets
    end

    it "allows you to overide enviroment settings" do
      Amber::Server.configure do |server|
        server.name = "Hello World App"
        server.port = 8080
        server.env = "fake_env"
        server.log = ::Logger.new(STDOUT)
        server.log.level = ::Logger::INFO
      end

      settings = Amber::Server.settings

      settings.name.should eq "Hello World App"
      settings.port.should eq 8080
      settings.env.should eq "fake_env"
      settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
    end

    it "should still retain environment.yml settings that haven't been overwritten" do
      # NOTE: Any changes to settings here remain for all specs run afterwards.
      # This is a problem.

      Amber::Server.configure do |server|
        server.name = "Hello World App"
        server.port = 8080
      end

      settings = Amber::Server.settings

      settings.name.should eq "Hello World App"
      settings.port.should eq 8080
      settings.env.should eq "fake_env"
      expected_secrets = {
        description: "Store your test secrets credentials and settings here.",
        database:    "mysql://root@localhost:3306/amber_test_app_test",
      }
      settings.secrets.should eq expected_secrets
      settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
    end
  end
end
