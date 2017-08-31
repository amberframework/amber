require "../../spec_helper"

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

      server = Amber::Server

      server.settings.name.should eq "Hello World App"
      server.settings.port.should eq 8080
      server.settings.env.should eq "development"
      server.settings.secret.should eq "some secret key"
    end
  end
end
