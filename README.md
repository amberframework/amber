# Welcome to Amber

**Amber** is a web application framework written in Crystal (http://www.crystal-lang.org) inspired by Kemal, Rails, Phoenix
and other popular application frameworks.

The purpose of Amber was not to create yet another framework, but to take advantage of a beautiful language capabilities
and provide engineers an efficient, cohesive, and well maintian web framework that embraces the Crystal language
philosophies, conventions and guides.

Crystal will borrow concepts that already have been successful, we will embrace new concepts through team/community
collaboration and analysis, that align with Amber and Crystal philosphies.

## Amber Philosophies H.R.T.

It's all about the community. Software development is a team sport!

It's not enough to be brilliant when you're alone in your programming lair. You are not going to change the world or
delight millions of users by hidding and preparing your secret invention. We need to work with other members, we need to
share our visions, devide the labor, learn from others, we need to be a team.

**HUMILITY** We are not the center of the universe. You're neither omnicient nor infalible. You are open to self-improvemnt.

**RESPECT** You genuinly care about others you work with. You treat them as human beingsm and appreciate their abilities
and accomplishments.

**TRUST** You believe others are competent and will do the right thing, and you are OK with letting them drive when
appropiate.

## Code of Conduct

We have adopted the Contributor Covenant to be our (CODE OF CONDUCT)[CODE_OF_CONDUCT.md] guidelines for Amber.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  amber:
    github: eliasjpr/amber
```

## Usage

```crystal
require "amber"
```

```crystal
# Location for your initialization code
# {YourApp}/src/config/app.cr

# The config file that Amber generates, web/router.cr, will look something like
# this one:

# The first line requires the framework library.
require "./amber"

# This line simply makes a Amber Server instance that will be use for your
# entire application
MyAwesomeApp = Amber::Server.instance

# This line represents how you will define your application configuration.
MyAwesomeApp.config do
  # Server options
  app_path = __FILE__ # Do not change unless you understand what you are doing.
  name = "Hello World App" # A descriptive name for your app
  port = 8080 # Port you wish your app to run
  env = "development".colorize(:yellow).to_s
  log = ::Logger.new(STDOUT)
  log.level = ::Logger::INFO

  # Every Amber application needs to define a pipeline set of pipes
  # each pipelines allow a set of middleware transformations to be applied to
  # different sets of route, this give you granular control and explicitnes
  # of which transformation to run for each of the app request.

  # All api scoped routes will run these transformations
  pipeline :api do
    # Plug is the method to use add a pipe (middleware)
    # A plug accepts an instance of HTTP::Handler
    # Note: We recomment to use singleton patter for middlewares.
    plug Amber::Pipe::Params.instance
    plug Amber::Pipe::Logger.instance
    plug Amber::Pipe::Error.instance
    plug Amber::Pipe::Session.instance
  end

  # All static content will run these transformations
  pipeline :static do
    plug Amber::Pipe::Params.instance
    plug Amber::Pipe::Logger.instance
    plug Amber::Pipe::Error.instance
    plug Amber::Pipe::Session.instance
  en

  # This is how you define the routes for your application
  # HTTP methods supported [GET, PATCH, POST, PUT, DELETE, OPTIONS]
  # Read more about HTTP methods here
  # (HTTP METHODS)[https://www.w3.org/Protocols/rfc2616/rfc2616-sec9.html]
  routes do
    # each route is defined as follow
    # verb, resources : String, controller : Symbol, action : Symbol,
    # pipeline : Symbol
    get "/", :elias, :perez, :api
    get "/elias", :elias, :perez, :api
    get "/elias/:role", :elias, :perez, :api
  end
end

# Finally this is how you will bootup the server.
MyAwesomeApp.run
```

## Contributing

1. Fork it ( https://github.com/eliasjpr/amber/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [eliasjpr](https://github.com/eliasjpr) Elias Perez - creator, maintainer

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by Kemal, Rails, Phoenix, Kemalyst
