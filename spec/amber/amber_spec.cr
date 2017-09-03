require "../../spec_helper"

struct UserSocket < Amber::WebSockets::ClientSocket; end

struct RoomSocket < Amber::WebSockets::ClientSocket; end

describe Amber::Server do
  describe ".configure" do
    it "starts the server" do
      Amber::Server.configure do |server|
        server.name = "Hello World App"
        server.port = 8080
        server.env = "development"
        server.log = ::Logger.new(STDOUT)
        server.log.level = ::Logger::INFO
        server.secret = "some secret key"
      end

      settings = Amber::Server.settings

      settings.name.should eq "Hello World App"
      settings.port.should eq 8080
      settings.env.should eq "development"
      settings.secret.should eq "some secret key"
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
