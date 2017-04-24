require "./spec_helper"

describe Amber do
  describe "Running the server" do
    it "boots up the server" do
      my_awesome_app = Amber::Server.instance

      my_awesome_app.config do
        name = "Hello World App"
        port = 8080
        env = "development".colorize(:yellow).to_s
        log = ::Logger.new(STDOUT)
        log.level = ::Logger::INFO
        secret = "some secret key"

        pipeline :api do
          plug Amber::Pipe::Params.instance
          plug Amber::Pipe::Logger.instance
          plug Amber::Pipe::Error.instance
          plug Amber::Pipe::Session.instance
        end

        pipeline :static do
          plug Amber::Pipe::Params.instance
          plug Amber::Pipe::Logger.instance
          plug Amber::Pipe::Error.instance
          plug Amber::Pipe::Session.instance
        end

        routes do
          get "/", HelloController, :world, :api
          get "/hello", HelloController, :world, :api
          get "/hello/:role", HelloController, :world, :api
        end
      end
    end
  end
end
