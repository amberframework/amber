require "../spec_helper"

struct UserSocket < Amber::WebSockets::ClientSocket; end

struct RoomSocket < Amber::WebSockets::ClientSocket; end

describe Amber do
  describe Amber::Server do
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
