# Routing

Amber V2 includes an internalized router that is significantly faster than the original `amber_router` shard. Routes are defined using a macro-based DSL inside `Amber::Server.configure`, supporting all HTTP methods, RESTful resources, namespaces, WebSocket routes, route constraints, API versioning, and named routes.

## Quick Start

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
  end
end
```

## Route Definition

Routes map an HTTP method and URL pattern to a controller and action.

### HTTP Methods

```crystal
routes :web do
  get    "/items",     ItemsController, :index
  post   "/items",     ItemsController, :create
  put    "/items/:id", ItemsController, :update
  patch  "/items/:id", ItemsController, :update
  delete "/items/:id", ItemsController, :destroy
  head   "/items",     ItemsController, :index
end
```

All available route methods: `get`, `post`, `put`, `patch`, `delete`, `options`, `head`, `trace`, `connect`.

When you define a `get` route, a corresponding `head` route is automatically added. When you define any route other than `trace`, `connect`, `options`, or `head`, a corresponding `options` route is automatically added.

### URL Parameters

Use `:param` syntax for dynamic URL segments:

```crystal
routes :web do
  get "/users/:id",            UsersController, :show
  get "/users/:user_id/posts", PostsController, :index
end
```

Parameters are accessible in the controller via `params`:

```crystal
class UsersController < ApplicationController
  def show
    user_id = params["id"]
    # ...
  end
end
```

### Glob Parameters

Use `*` for catch-all segments:

```crystal
routes :web do
  get "/files/*path", FilesController, :show
end
```

## Resources

The `resources` macro generates all seven RESTful routes for a resource:

```crystal
routes :web do
  resources "posts", PostsController
end
```

This generates:

| HTTP Method | Path | Action | Description |
|------------|------|--------|-------------|
| GET | `/posts` | `:index` | List all posts |
| GET | `/posts/new` | `:new` | New post form |
| POST | `/posts` | `:create` | Create a post |
| GET | `/posts/:id` | `:show` | Show a post |
| GET | `/posts/:id/edit` | `:edit` | Edit post form |
| PUT/PATCH | `/posts/:id` | `:update` | Update a post |
| DELETE | `/posts/:id` | `:destroy` | Delete a post |

### Limiting Resource Actions

```crystal
# Only generate specific actions
resources "posts", PostsController, only: [:index, :show]

# Generate all except specific actions
resources "posts", PostsController, except: [:destroy]
```

## Namespaces

Group routes under a URL prefix:

```crystal
routes :web do
  namespace "/admin" do
    resources "users", Admin::UsersController
    resources "posts", Admin::PostsController
  end
end
```

This generates routes like `/admin/users`, `/admin/posts`, etc.

### Nested Namespaces

```crystal
routes :web do
  namespace "/api" do
    namespace "/v1" do
      resources "items", Api::V1::ItemsController
    end
  end
end
```

## Pipelines

Pipelines are ordered sequences of middleware (pipes) that process requests before they reach the controller. Define pipelines and assign routes to them.

```crystal
Amber::Server.configure do
  # Define pipelines
  pipeline :web do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::Flash.new
    plug Amber::Pipe::CSRF.new
  end

  pipeline :api do
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::CORS.new
  end

  # Assign routes to pipelines
  routes :web do
    get "/", HomeController, :index
    resources "users", UsersController
  end

  routes :api do
    get "/api/items", Api::ItemsController, :index
    post "/api/items", Api::ItemsController, :create
  end
end
```

### Built-in Pipes

| Pipe | Description |
|------|-------------|
| `Amber::Pipe::Error` | Error handling and exception pages |
| `Amber::Pipe::Logger` | Request logging |
| `Amber::Pipe::Session` | Session management |
| `Amber::Pipe::Flash` | Flash messages |
| `Amber::Pipe::CSRF` | CSRF protection |
| `Amber::Pipe::CORS` | Cross-Origin Resource Sharing |
| `Amber::Pipe::Static` | Static file serving |
| `Amber::Pipe::PoweredByAmber` | Adds X-Powered-By header |
| `Amber::Pipe::ClientIp` | Client IP detection |

## Route Constraints

Constraints restrict which requests can match a route based on headers, host, subdomain, or other criteria.

### Using Constraints

```crystal
routes :web do
  constraint(Amber::Router::Constraints::Host.new("admin.example.com")) do
    resources "users", Admin::UsersController
  end

  constraint(Amber::Router::Constraints::Subdomain.new("api")) do
    get "/items", Api::ItemsController, :index
  end

  constraint(Amber::Router::Constraints::Header.new("X-Api-Key", /^sk_/)) do
    resources "items", Api::ItemsController
  end

  constraint(Amber::Router::Constraints::Accept.new("application/json")) do
    get "/data", DataController, :index
  end
end
```

### Built-in Constraint Types

| Constraint | Description |
|-----------|-------------|
| `Constraints::Host` | Match by full hostname |
| `Constraints::Subdomain` | Match by subdomain |
| `Constraints::Header` | Match by request header value |
| `Constraints::Accept` | Match by Accept header content type |

### URL Parameter Constraints

Route-level parameter constraints use regex patterns:

```crystal
routes :web do
  get "/users/:id", UsersController, :show, constraints: {"id" => /\d+/}
  get "/posts/:slug", PostsController, :show, constraints: {"slug" => /[a-z0-9\-]+/}
end
```

## API Versioning

The `api_version` macro supports three versioning strategies:

### URL-Based (Default)

```crystal
routes :api do
  api_version "v1", strategy: :url do
    get "/items", Api::V1::ItemsController, :index
  end

  api_version "v2", strategy: :url do
    get "/items", Api::V2::ItemsController, :index
  end
end
```

Generates routes: `/v1/items`, `/v2/items`

### Header-Based

```crystal
routes :api do
  api_version "v1", strategy: :header, header: "Api-Version" do
    get "/items", Api::V1::ItemsController, :index
  end

  api_version "v2", strategy: :header, header: "Api-Version" do
    get "/items", Api::V2::ItemsController, :index
  end
end
```

Routes are matched when the `Api-Version` header matches the version string.

### Media Type-Based

```crystal
routes :api do
  api_version "v1", strategy: :media_type, media_type: "application/vnd.myapp" do
    get "/items", Api::V1::ItemsController, :index
  end
end
```

Routes are matched when the `Accept` header contains the specified media type and version.

## Named Routes

Assign names to routes for use in path/URL generation:

```crystal
routes :web do
  get "/users/:id", UsersController, :show, route_name: :user
  get "/users", UsersController, :index, route_name: :users
end
```

### Generating Paths and URLs

In controllers:

```crystal
class UsersController < ApplicationController
  def show
    # Generate a path
    path = route_path(:user, id: "5")
    # => "/users/5"

    # Generate a full URL
    url = route_url(:user, id: "5")
    # => "http://localhost:3000/users/5"

    # Extra params become query string
    path = route_path(:users, page: "2")
    # => "/users?page=2"
  end
end
```

The `NamedRoutes` module can also be used directly:

```crystal
Amber::Router::NamedRoutes.path(:user, id: "5")
Amber::Router::NamedRoutes.url(:user, id: "5")
```

## WebSocket Routes

Define WebSocket endpoints within route blocks:

```crystal
routes :web do
  websocket "/ws", UserSocket
  websocket "/admin/ws", AdminSocket
end
```

See the [WebSockets Guide](websockets.md) for full WebSocket documentation.

## Route Introspection

The router supports inspecting registered routes at runtime via the `RoutePrinter`:

```crystal
Amber::Server.router.route_list
```

This is useful for debugging and building admin panels that display all application routes.

## Source Files

- `src/amber/dsl/router.cr` -- Route DSL (get, post, resources, namespace, constraint, api_version, websocket)
- `src/amber/dsl/server.cr` -- Server DSL (routes, pipeline)
- `src/amber/dsl/schema_router.cr` -- Schema-aware router variant
- `src/amber/router/router.cr` -- Core router implementation
- `src/amber/router/route.cr` -- Route struct
- `src/amber/router/route_info.cr` -- Route information for introspection
- `src/amber/router/route_printer.cr` -- Route list printer
- `src/amber/router/named_routes.cr` -- Named route path/URL generation
- `src/amber/router/scope.cr` -- Namespace/scope management
- `src/amber/router/constraint.cr` -- Constraint base class
- `src/amber/router/constraints/` -- Built-in constraint implementations (accept, header, host, subdomain)
- `src/amber/router/engine/` -- Internalized trie-based route matching engine
- `src/amber/pipes/pipeline.cr` -- Pipeline middleware system
