require "../../spec_helper"

struct UserSocket < Amber::WebSockets::ClientSocket; end

struct RoomSocket < Amber::WebSockets::ClientSocket; end

describe Amber::Server do
  describe ".configure" do
    it "it loads environment settings from test.yml" do
      settings = Amber::Server.settings

      settings.name.should eq "amber_test_app"
      settings.port_reuse.should eq true
      settings.redis_url.should eq "#{ENV["REDIS_URL"]? || "redis://localhost:6379"}"
      settings.port.should eq 3000
      settings.env.should eq "test"
      settings.color.should eq true
      settings.secret_key_base.should eq "mV6kTmG3k1yVFh-fPYpugSn0wbZveDvrvfQuv88DPF8"
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
        server.color = false
      end

      settings = Amber::Server.settings

      settings.name.should eq "Hello World App"
      settings.port.should eq 8080
      settings.env.should eq "fake_env"
      settings.color.should eq false
      settings.secret_key_base.should eq "mV6kTmG3k1yVFh-fPYpugSn0wbZveDvrvfQuv88DPF8"
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
      settings.secret_key_base.should eq "mV6kTmG3k1yVFh-fPYpugSn0wbZveDvrvfQuv88DPF8"
    end

    it "defines socket endpoint" do
      Amber::Server.settings.router.socket_routes = [] of NamedTuple(path: String, handler: Amber::WebSockets::Server::Handler)

      Amber::Server.configure do |app|
        pipeline :web do
        end

        routes :web do
          websocket "/user", UserSocket
          websocket "/room", RoomSocket
        end
      end

      router = Amber::Server.settings.router
      websockets = router.socket_routes

      websockets[0][:path].should eq "/user"
      websockets[0][:handler].is_a?(Amber::WebSockets::Server::Handler).should be_true
      websockets[1][:path].should eq "/room"
      websockets[1][:handler].is_a?(Amber::WebSockets::Server::Handler).should be_true
    end
  end
end
