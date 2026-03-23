---
name: amber-routing
description: Amber V2 routing DSL — route definitions, resourceful routes, named routes, constraints, API versioning, scoping, and route introspection
user-invocable: false
---

# Amber Routing

Routes map HTTP requests to controller actions. Defined inside `routes :pipeline_name` blocks in the server configuration.

## Route DSL

```crystal
Amber::Server.configure do
  pipeline :web do
    # ... pipes
  end

  routes :web do
    get "/", HomeController, :index
    get "/about", PagesController, :about
    post "/login", SessionsController, :create
  end
end
```

### HTTP Verb Methods

All standard HTTP verbs are available as macros:

```crystal
get    "/path", Controller, :action
post   "/path", Controller, :action
put    "/path", Controller, :action
patch  "/path", Controller, :action
delete "/path", Controller, :action
options "/path", Controller, :action
head   "/path", Controller, :action
```

- `get` routes automatically register a `HEAD` route too
- `get`, `post`, `put`, `patch`, `delete` automatically register an `OPTIONS` route

## Resourceful Routes

The `resources` macro generates standard CRUD routes:

```crystal
routes :web do
  resources "posts", PostsController
end
```

This generates:

| HTTP Verb | Path | Action | Purpose |
|-----------|------|--------|---------|
| GET | /posts | :index | List all |
| GET | /posts/new | :new | New form |
| POST | /posts | :create | Create |
| GET | /posts/:id | :show | Show one |
| GET | /posts/:id/edit | :edit | Edit form |
| PUT/PATCH | /posts/:id | :update | Update |
| DELETE | /posts/:id | :destroy | Delete |

### Limiting Resource Actions

```crystal
# Only specific actions
resources "posts", PostsController, only: [:index, :show]

# All except specific actions
resources "posts", PostsController, except: [:destroy]
```

## Route Parameters

Dynamic segments start with `:`:

```crystal
get "/users/:id", UsersController, :show
get "/posts/:post_id/comments/:id", CommentsController, :show
```

Access in controllers via `params[:id]`, `params[:post_id]`.

Glob segments capture the rest of the path:

```crystal
get "/files/*filepath", FilesController, :show
# /files/docs/readme.md → params["filepath"] = "docs/readme.md"
```

## Parameter Constraints

Constrain route parameters with regex patterns:

```crystal
# Inline regex constraint
get "/users/:id", UsersController, :show, constraints: {"id" => /\d+/}

# Multiple constraints
get "/posts/:year/:month", PostsController, :archive,
  constraints: {"year" => /\d{4}/, "month" => /\d{2}/}
```

### Preset Constraints

Built-in regex presets available via `Amber::Router::CONSTRAINT_PRESETS`:

| Preset | Pattern | Matches |
|--------|---------|---------|
| `:numeric` | `/\A\d+\z/` | Digits only |
| `:uuid` | UUID v4 pattern | `550e8400-e29b-41d4-a716-446655440000` |
| `:slug` | `/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/` | URL slugs |
| `:alpha` | `/\A[a-zA-Z]+\z/` | Letters only |
| `:alnum` | `/\A[a-zA-Z0-9]+\z/` | Alphanumeric |
| `:hex` | `/\A[0-9a-fA-F]+\z/` | Hex strings |

Source: `src/amber/router/constraint_presets.cr`

## Named Routes

Name routes for path/URL generation:

```crystal
routes :web do
  get "/users/:id", UsersController, :show, route_name: :user
  get "/posts", PostsController, :index, route_name: :posts
end
```

### Generating Paths and URLs

```crystal
# In controllers (instance methods on Base)
route_path(:user, id: 5)     # => "/users/5"
route_url(:user, id: 5)      # => "http://localhost:3000/users/5"

# Extra params become query string
route_path(:posts, page: 2)  # => "/posts?page=2"

# Module-level (anywhere in your code)
Amber::Router::NamedRoutes.path(:user, id: 5)
Amber::Router::NamedRoutes.url(:user, id: 5)
```

Source: `src/amber/router/named_routes.cr`

## Namespacing (Scoping)

Group routes under a path prefix:

```crystal
routes :web do
  namespace "/admin" do
    resources "users", Admin::UsersController
    # Generates: /admin/users, /admin/users/:id, etc.
  end

  namespace "/api" do
    namespace "/v1" do
      get "/posts", Api::V1::PostsController, :index
      # Generates: /api/v1/posts
    end
  end
end
```

## Request-Level Constraints

Constrain entire route groups based on request properties (host, subdomain, headers):

```crystal
routes :web do
  # Host constraint
  constraint(Amber::Router::Constraints::Host.new("api.example.com")) do
    get "/users", Api::UsersController, :index
  end

  # Subdomain constraint
  constraint(Amber::Router::Constraints::Subdomain.new("admin")) do
    resources "dashboard", Admin::DashboardController
  end

  # Header constraint
  constraint(Amber::Router::Constraints::Header.new("X-Internal", "true")) do
    get "/debug", DebugController, :index
  end

  # Accept header / media type constraint
  constraint(Amber::Router::Constraints::Accept.new("application/vnd.myapp", "v2")) do
    get "/users", Api::V2::UsersController, :index
  end
end
```

### Built-in Constraint Classes

| Class | Constructor | Matches |
|-------|-------------|---------|
| `Constraints::Host` | `Host.new("example.com")` | Exact host match |
| `Constraints::Subdomain` | `Subdomain.new("admin")` | Host starts with subdomain |
| `Constraints::Header` | `Header.new("X-Key", "value")` | Header has exact value |
| `Constraints::Accept` | `Accept.new("media_type", "version")` | Accept header contains media type + version |

### Custom Constraints

Implement `Amber::Router::Constraint`:

```crystal
class BusinessHoursConstraint
  include Amber::Router::Constraint

  def matches?(request : HTTP::Request) : Bool
    now = Time.local
    now.hour >= 9 && now.hour < 17
  end
end

# Usage
constraint(BusinessHoursConstraint.new) do
  get "/support", SupportController, :index
end
```

Source: `src/amber/router/constraint.cr`, `src/amber/router/constraints/`

## API Versioning

Three strategies for API version routing:

```crystal
routes :api do
  # URL-based (default): /v1/users, /v2/users
  api_version "v1", strategy: :url do
    get "/users", Api::V1::UsersController, :index
  end

  # Header-based: requires Api-Version: v1 header
  api_version "v1", strategy: :header do
    get "/users", Api::V1::UsersController, :index
  end

  # Media type: requires Accept: application/vnd.amber.v1+json
  api_version "v1", strategy: :media_type do
    get "/users", Api::V1::UsersController, :index
  end

  # URL-based with custom prefix
  api_version "v2", strategy: :url, prefix: "/api" do
    get "/users", Api::V2::UsersController, :index
    # Generates: /api/v2/users
  end

  # Header-based with custom header name
  api_version "v1", strategy: :header, header: "X-API-Version" do
    get "/users", Api::V1::UsersController, :index
  end

  # Media type with custom media type
  api_version "v1", strategy: :media_type, media_type: "application/vnd.myapp" do
    get "/users", Api::V1::UsersController, :index
  end
end
```

Source: `src/amber/dsl/router.cr:63-77`

## WebSocket Routes

```crystal
routes :web do
  websocket "/chat", ChatSocket
end
```

Source: `src/amber/dsl/router.cr:126-128`

## Route Introspection

Print all registered routes:

```crystal
Amber::Server.router.print_routes
```

Source: `src/amber/router/route_printer.cr`

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/dsl/router.cr` | Route DSL: verb macros, resources, namespace, constraint, api_version |
| `src/amber/dsl/server.cr` | `pipeline` and `routes` macros |
| `src/amber/router/router.cr` | Router class with `draw` and `add` methods |
| `src/amber/router/named_routes.cr` | `NamedRoutes.path` and `.url` helpers |
| `src/amber/router/constraint.cr` | `Constraint` module (abstract interface) |
| `src/amber/router/constraint_presets.cr` | Built-in regex presets (numeric, uuid, slug, etc.) |
| `src/amber/router/constraints/host.cr` | Host matching constraint |
| `src/amber/router/constraints/subdomain.cr` | Subdomain matching constraint |
| `src/amber/router/constraints/header.cr` | Header value matching constraint |
| `src/amber/router/constraints/accept.cr` | Accept header / media type constraint |
| `src/amber/router/scope.cr` | Scope stack for namespacing |
| `src/amber/router/context.cr` | HTTP::Server::Context extensions |
| `src/amber/router/route_printer.cr` | Route table printing |
| `src/amber/controller/helpers/route.cr` | `action_name`, `route_resource`, etc. |
