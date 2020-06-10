require "../spec_helper"

struct UserSocket < Amber::WebSockets::ClientSocket; end

struct RoomSocket < Amber::WebSockets::ClientSocket; end

describe Amber do
  describe ".env" do
    it "should return test" do
      Amber.env.test?.should be_truthy
      Amber.env.==(:test).should be_truthy
      Amber.env.==(:development).should be_falsey
      Amber.env.!=(:development).should be_truthy
      Amber.env.!=(:test).should be_falsey
    end
  end

  describe ".env=" do
    context "when switching environments" do
      it "changes environment from TEST to PRODUCTION" do
        current_settings = Amber.settings
        Amber.env = :production
        current_settings.port.should eq 3000
        Amber.settings.port.should eq 4000
      end

      it "sets Amber environment from yaml settings file" do
        Amber.env = :development
        Amber.settings.name.should eq "development_settings"
      end
    end
  end

  describe Amber::Server do
    describe ".configure" do
      it "overrides current environment settings" do
        Amber.env = :test

        Amber::Server.configure do |server|
          server.name = "Hello World App"
          server.port = 8080
          server.logging.colorize = false
          server.logging.filter = %w(password confirm_password)
        end

        settings = Amber.settings

        settings.name.should eq "Hello World App"
        settings.port.should eq 8080
        settings.logging.colorize.should eq false
        settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
        settings.logging.filter.should eq %w(password confirm_password)
      end

      it "retains environment.yml settings that haven't been overwritten" do
        Amber.env = :test
        expected_session = {:key => "amber.session", :store => :signed_cookie, :expires => 0}
        expected_secrets = {
          "description" => "Store your test secrets credentials and settings here.",
        }

        Amber::Server.configure do |server|
          server.name = "Fake App Name"
          server.port = 8080
        end
        settings = Amber.settings

        settings.name.should eq "Fake App Name"
        settings.port_reuse.should eq true
        settings.redis_url.should eq "redis://localhost:6379"
        settings.logging.colorize.should eq true
        settings.secret_key_base.should eq "ox7cTo_408i4WZkKZ_5OZZtB5plqJYhD4rxrz2hriA4"
        settings.session.should eq expected_session
        settings.port.should eq 8080
        settings.database_url.should eq "mysql://root@localhost:3306/test_settings_test"
        settings.secrets.should eq expected_secrets
      end

      it "defines socket endpoint" do
        Amber::Server.router.socket_routes = [] of NamedTuple(path: String, handler: Amber::WebSockets::Server::Handler)

        Amber::Server.configure do
          pipeline :web do
          end

          routes :web do
            websocket "/user", UserSocket
            websocket "/room", RoomSocket
          end
        end

        router = Amber::Server.router
        websockets = router.socket_routes

        websockets[0][:path].should eq "/user"
        websockets[0][:handler].is_a?(Amber::WebSockets::Server::Handler).should be_true
        websockets[1][:path].should eq "/room"
        websockets[1][:handler].is_a?(Amber::WebSockets::Server::Handler).should be_true
      end
    end
  end
end
