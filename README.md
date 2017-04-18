![Amber Crystal Framework](https://github.com/Amber-Crystal/amber/blob/master/media/amber.png)

[![Build Status](https://travis-ci.org/Amber-Crystal/amber.svg?branch=master)](https://travis-ci.org/Amber-Crystal/amber)
[![Code Triagers Badge](https://www.codetriage.com/amber-crystal/amber/badges/users.svg)](https://www.codetriage.com/amber-crystal/amber)
# Welcome to Amber

**Amber** is a web application framework written in [Crystal](http://www.crystal-lang.org) inspired by Kemal, Rails, Phoenix and other popular application frameworks.

The purpose of Amber is not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers an efficient, cohesive, and well maintain web framework for the crystal community that embraces the language philosophies, conventions, and guides.

Ambar Crystal borrows concepts that already have been battle tested, successful, and embrace new concepts through team and community collaboration and analysis, that aligns with Crystal philosophies.

## Amber Philosophy H.R.T.

*It's all about the community. Software development is a team sport!*

It's not enough to be brilliant when you're alone in your programming lair. You are not going to change the world or delight millions of users by hiding and preparing your secret invention. We need to work with other members, we need to share our visions, divide the labor, learn from others, we need to be a team.

**HUMILITY** We are not the center of the universe. You're neither omniscient nor infallible. You are open to self-improvement.

**RESPECT** You genuinely care about others you work with. You treat them as human beings and appreciate their abilities and accomplishments.

**TRUST** You believe others are competent and will do the right thing, and you are OK with letting them drive when appropriate.
appropiate.

## Become a Contributor

Contributing to Amber can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Amber.

Amber is a community effort and we want You to be part of ours [Join Amber Community!](https://github.com/Amber-Crystal/amber/blob/master/.github/CONTRIBUTING.md)

## Code of Conduct

We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](CODE_OF_CONDUCT.md) guidelines for Amber.

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
  # each pipeline allow a set of middleware transformations to be applied to
  # different sets of route, this give you granular control and explicitness
  # of which transformation to run for each of the app requests.

  # All api scoped routes will run these transformations
  pipeline :api do
    # Plug is the method to use connect a pipe (middleware)
    # A plug accepts an instance of HTTP::Handler
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
    # Each route is defined as follow
    # verb, resources : String, controller : Symbol, action : Symbol,
    # pipeline : Symbol
    get "/", :hello, :world, :api
    get "/hello", :hello, :world, :api
    get "/hello/:planet", :hello, :world, :api
  end
end

# Finally this is how you will bootup the server.
MyAwesomeApp.run
```

## Contributing

1. Fork it (https://github.com/Amber-Crystal/amber)
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [eliasjpr](https://github.com/eliasjpr) Elias Perez - creator, maintainer
- [fridgerator](https://github.com/fridgerator) Nick Franken - Maintainer
- [elorest](https://github.com/elorest) Isaac Sloan - Maintainer
- [phoffer](https://github.com/phoffer) Paul Hoffer - Maintainer
- [bew](https://github.com/fridgerator) Benoit de Chezelles - Member

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by Kemal, Rails, Phoenix
