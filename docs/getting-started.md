# Getting Started

This guide walks through creating a minimal Amber V2 application from scratch. By the end, you will have a working web server that responds to HTTP requests with a rendered HTML page.

## Prerequisites

- [Crystal](https://crystal-lang.org/install/) >= 1.0.0
- A text editor

## Create a New Project

Create a new Crystal project using `crystal init`:

```bash
crystal init app my_app
cd my_app
```

## Add Amber as a Dependency

Edit `shard.yml` to add the Amber framework:

```yaml
name: my_app
version: 0.1.0

dependencies:
  amber:
    github: amberframework/amber
    branch: v2-dev

crystal: ">= 1.0.0"
```

Install dependencies:

```bash
shards install
```

## Project Structure

Create the following directory structure:

```
my_app/
  src/
    my_app.cr
    controllers/
      home_controller.cr
    views/
      home/
        index.ecr
      layouts/
        application.ecr
```

Create the directories:

```bash
mkdir -p src/controllers src/views/home src/views/layouts
```

## Create a Controller

Create `src/controllers/home_controller.cr`:

```crystal
require "amber/controller/base"

class HomeController < Amber::Controller::Base
  def index
    @title = "Welcome"
    render("index.ecr")
  end
end
```

The `render` macro looks for the template at `src/views/home/index.ecr` based on the controller name. It wraps the template in the default layout at `src/views/layouts/application.ecr`.

## Create Views

Create the layout at `src/views/layouts/application.ecr`:

```ecr
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>My App</title>
</head>
<body>
  <%= content %>
</body>
</html>
```

The `<%= content %>` placeholder is where the action template is inserted.

Create the index template at `src/views/home/index.ecr`:

```ecr
<h1><%= @title %></h1>
<p>Hello from Amber V2!</p>
```

## Configure the Server

Edit `src/my_app.cr` to configure routing and start the server:

```crystal
require "amber"
require "./controllers/*"

Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
  end

  routes :web do
    get "/", HomeController, :index
  end
end

Amber::Server.start
```

This configures a `:web` pipeline with error handling and request logging, maps `GET /` to `HomeController#index`, and starts the HTTP server.

## Run the Application

```bash
crystal run src/my_app.cr
```

Visit `http://localhost:3000` in your browser to see your page.

## Configuration

By default, Amber listens on `localhost:3000`. To change the host or port, create a YAML configuration file or use environment variables.

### Environment Variables

```bash
AMBER_SERVER_HOST=0.0.0.0 AMBER_SERVER_PORT=8080 crystal run src/my_app.cr
```

### YAML Configuration

Create `config/environments/development.yml`:

```yaml
name: "my_app"

server:
  host: "localhost"
  port: 3000
  secret_key_base: "a_random_string_at_least_32_characters_long"

logging:
  severity: "debug"
  colorize: true
```

See the [Configuration Guide](guides/configuration.md) for all available settings.

## Adding More Routes

Add additional routes and controllers as your application grows:

```crystal
Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::Flash.new
    plug Amber::Pipe::CSRF.new
  end

  routes :web do
    get "/", HomeController, :index
    resources "users", UsersController
    resources "posts", PostsController
  end
end
```

The `resources` macro generates all seven RESTful routes (index, new, create, show, edit, update, destroy) for a given controller.

## Next Steps

- [Routing](guides/routing.md) -- Route definitions, resources, namespaces, constraints, and API versioning
- [Configuration](guides/configuration.md) -- Environment YAML, environment variables, and custom config sections
- [Action Helpers](guides/action-helpers.md) -- Form helpers, URL helpers, asset tags, and text formatting
- [Schema API](guides/schema-api.md) -- Type-safe, validated parameter handling
- [WebSockets](guides/websockets.md) -- Real-time communication with channels and presence tracking
- [Background Jobs](guides/background-jobs.md) -- Asynchronous job processing
- [Mailer](guides/mailer.md) -- Email delivery with SMTP and memory adapters
- [Testing](guides/testing.md) -- Request helpers, assertions, and controller testing
- [Markdown](guides/markdown.md) -- Markdown rendering with GFM support
- [Migration Guide](migration-guide.md) -- Migrating from Amber V1 to V2
