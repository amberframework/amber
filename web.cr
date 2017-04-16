require "./amber"

class EliasController < Amber::Controller
  def perez
    "Nice framework Elias!"
  end
end

MyAwesomeApp = Amber::Server.instance

MyAwesomeApp.config do
  app_path = __FILE__
  name = "My Awesome App"
  port = 8080
  env = "development".colorize(:yellow).to_s
  log = ::Logger.new(STDOUT)
  log.level = ::Logger::INFO

  pipeline :api do
    plug Amber::Pipe::Logger.instance
  end

  routes do
    get "/", :elias, :perez, :api
    get "/elias", :elias, :perez, :api
    get "/elias/:role", :elias, :perez, :api
  end
end

MyAwesomeApp.run