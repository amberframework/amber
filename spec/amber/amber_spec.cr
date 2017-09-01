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

      settings = Amber::Server.settings

      settings.name.should eq "Hello World App"
      settings.port.should eq 8080
      settings.env.should eq "development"
      settings.secret.should eq "some secret key"
    end
  end
end
