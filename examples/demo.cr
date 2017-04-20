

# Location for your initialization code
# {YourApp}/src/config/app.cr

# The config file that Amber generates, web/router.cr, will look something like
# this one:

# The first line requires the framework library.
require "../src/amber"
# This line simply makes a Amber Server instance that will be use for your
# entire application
MyAwesomeApp = Amber::Server.instance

class HelloController < Amber::Controller
    def world
        "Server Running!"
    end
end

# This line represents how you will define your application configuration.
MyAwesomeApp.config do
  # Server options
  app_path = __FILE__ # Do not change unless you understand what you are doing.
  name = "Hello World App" # A descriptive name for your app
  port = 8080 # Port yu wish your app to run
  env = "development".colorize(:yellow).to_s
  log = ::Logger.new(STDOUT)
  log.level = ::Logger::INFO

  # Every Amber application needs to define a pipeline set of pipes
  # each pipeline allow a set of middleware transformations to be applied to
  # different sets of route, this give you granular control and explicitness
  # of which transformation to run for each of the app requests.

  # All api scoped routes will run these transformations
  pipeline :api do
    # Plug is the method to use connect a pipe (middleware)
    # A plug accepts an instance of HTTP::Handler
  end

  # All static content will run these transformations
  pipeline :static do
    plug HTTP::StaticFileHandler.new "examples/public", true
    plug HTTP::CompressHandler.new
  end

  # This is how you define the routes for your application
  # HTTP methods supported [GET, PATCH, POST, PUT, DELETE, OPTIONS]
  # Read more about HTTP methods here
  # (HTTP METHODS)[https://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html]
  routes do
    # Each route is defined as follow
    # verb, resources : String, controller : Symbol, action : Symbol,
    # pipeline : Symbol
    get "/index.html", :hello, :world, :static
    get "/hello", :hello, :world, :api
    get "/hello/:planet", :hello, :world, :api
  end
end

# Finally this is how you will bootup the server.
MyAwesomeApp.run
