Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::Flash.new
    plug Amber::Pipe::CSRF.new
  end

  pipeline :static do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Static.new("./public")
  end

  pipeline :api do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
  end

  routes :web do
    get "/", HomeController, :index
  end

  # API routes must stay above the static block, whose wildcard GET route
  # would otherwise answer /api/... requests.
  routes :api do
    post "/api/subscribers", SubscribersController, :create
  end

  routes :static do
    get "/*", Amber::Controller::Static, :index
  end
end
