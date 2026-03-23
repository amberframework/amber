---
name: amber-pipelines
description: Amber V2 middleware pipeline system — pipe composition, built-in pipes, auth patterns, and custom pipe creation
user-invocable: false
---

# Amber Pipelines (Middleware System)

Pipelines are ordered sequences of HTTP handlers ("pipes") that process requests before they reach a controller. Each named pipeline serves a different concern (`:web` for browser requests, `:api` for JSON endpoints, etc.).

## Pipeline DSL

Pipelines are defined in the server configuration block using the `pipeline` macro:

```crystal
Amber::Server.configure do
  pipeline :web do
    plug Amber::Pipe::PoweredByAmber.new
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::Session.new
    plug Amber::Pipe::Flash.new
    plug Amber::Pipe::CSRF.new
  end

  pipeline :api do
    plug Amber::Pipe::PoweredByAmber.new
    plug Amber::Pipe::Error.new
    plug Amber::Pipe::Logger.new
    plug Amber::Pipe::ApiVersion.new(default_version: "v1")
    plug Amber::Pipe::CORS.new
  end

  routes :web do
    resources "/posts", PostsController
  end

  routes :api do
    get "/posts", Api::PostsController, :index
  end
end
```

Routes are bound to a pipeline via `routes :pipeline_name`. The `Amber::Pipe::Controller` pipe is automatically appended as the final pipe in every pipeline.

## Built-in Pipes

All pipes inherit from `Amber::Pipe::Base` (which includes `HTTP::Handler`).

### Amber::Pipe::Error
Catches exceptions and returns appropriate HTTP responses. Must be early in the pipeline.
- `Amber::Exceptions::RouteNotFound` → 404
- `Amber::Exceptions::Forbidden` → 403
- Any other `Exception` → 500
- Responds as JSON or HTML based on `Accept` header

Source: `src/amber/pipes/error.cr`

### Amber::Pipe::Logger
Logs request details: status, method, pipeline name, format, URL, elapsed time, headers, params, cookies, session.

```crystal
# Constructor
Amber::Pipe::Logger.new(
  filter : Array(String) = log_config.filter,  # param names to mask as FILTERED
  skip : Array(String) = log_config.skip        # param names to skip entirely
)
```

Source: `src/amber/pipes/logger.cr`

### Amber::Pipe::Session
Manages session persistence. After the request completes:
1. Touches adapter-based sessions for sliding expiration
2. Writes changed sessions back to the cookie

Source: `src/amber/pipes/session.cr`

### Amber::Pipe::Flash
Persists flash messages to the session after each request using the `_flash` session key.

Source: `src/amber/pipes/flash.cr`

### Amber::Pipe::CSRF
Cross-Site Request Forgery protection. Validates tokens on `PUT`, `POST`, `PATCH`, `DELETE` methods.

```crystal
# Constants
CHECK_METHODS = %w(PUT POST PATCH DELETE)
HEADER_KEY    = "X-CSRF-TOKEN"
PARAM_KEY     = "_csrf"
TOKEN_LENGTH  = 32

# Token strategies (class property)
Amber::Pipe::CSRF.token_strategy = Amber::Pipe::CSRF::PersistentToken  # default, BREACH-resistant
Amber::Pipe::CSRF.token_strategy = Amber::Pipe::CSRF::RefreshableToken  # simpler, single-use

# In templates — generate hidden input or meta tag
Amber::Pipe::CSRF.tag(context)      # => <input type="hidden" name="_csrf" value="..." />
Amber::Pipe::CSRF.metatag(context)  # => <meta name="_csrf" content="..." />
```

**PersistentToken** (default): Uses one-time-pad masking to generate unique tokens per request while maintaining the same underlying session token. Resistant to BREACH attacks.

**RefreshableToken**: Simpler strategy — each token is single-use and deleted from session after validation.

Source: `src/amber/pipes/csrf.cr`

### Amber::Pipe::CORS
Cross-Origin Resource Sharing. Handles preflight `OPTIONS` requests and sets CORS headers.

```crystal
Amber::Pipe::CORS.new(
  origins : Array(String | Regex) = ["*"],       # allowed origins
  methods : Array(String) = %w(POST PUT PATCH DELETE),  # allowed methods
  headers : Array(String) = %w(Accept Content-Type),    # allowed headers
  credentials : Bool = false,                    # allow credentials
  max_age : Int32? = 0,                          # preflight cache (seconds)
  expose_headers : Array(String)? = nil,         # headers exposed to browser
  vary : String? = nil                           # additional Vary header value
)
```

Source: `src/amber/pipes/cors.cr`

### Amber::Pipe::Static
Serves static files from the public directory. Inherits from `HTTP::StaticFileHandler`.

```crystal
Amber::Pipe::Static.new(
  public_dir : String,
  fallthrough : Bool = false,       # pass to next handler if file not found
  directory_listing : Bool = false  # never list directory contents by default
)
```

Source: `src/amber/pipes/static.cr`

### Amber::Pipe::ClientIp
Extracts client IP from reverse proxy headers (e.g., `X-Forwarded-For`) and sets `context.client_ip`.

```crystal
# Single header (default)
Amber::Pipe::ClientIp.new(header: "X-Forwarded-For")

# Multiple headers to check
Amber::Pipe::ClientIp.new(["X-Forwarded-For", "X-Real-IP"])
```

Source: `src/amber/pipes/client_ip.cr`

### Amber::Pipe::ApiVersion
Extracts API version from request headers and normalizes it to `X-Api-Version` for downstream use.

```crystal
Amber::Pipe::ApiVersion.new(
  header : String = "Api-Version",      # source header to read
  default_version : String? = nil       # fallback if header missing
)

# Controllers read the version via:
request.headers["X-Api-Version"]?
```

Source: `src/amber/pipes/api_version.cr`

### Amber::Pipe::PoweredByAmber
Adds `X-Powered-By: Amber` response header.

Source: `src/amber/pipes/powered_by_amber.cr`

### Amber::Pipe::Controller
Automatically appended as the last pipe. Calls `context.process_request` to invoke the matched controller action.

Source: `src/amber/pipes/controller.cr`

## Writing Custom Pipes

Inherit from `Amber::Pipe::Base` and implement `call`:

```crystal
class AuthenticationPipe < Amber::Pipe::Base
  def call(context : HTTP::Server::Context)
    if authenticated?(context)
      call_next(context)  # MUST call this to continue the pipeline
    else
      context.response.status_code = 401
      context.response.print("Unauthorized")
    end
  end

  private def authenticated?(context)
    # Check session, token, etc.
    context.session["user_id"]?
  end
end
```

Key rules:
- Always call `call_next(context)` to pass to the next pipe (unless short-circuiting)
- Place auth pipes AFTER Session and BEFORE Controller in the pipeline
- Order matters — pipes execute top-to-bottom on request, bottom-to-top on response

## Common Pipeline Patterns

### Authenticated web pipeline
```crystal
pipeline :web do
  plug Amber::Pipe::Error.new
  plug Amber::Pipe::Logger.new
  plug Amber::Pipe::Session.new
  plug Amber::Pipe::Flash.new
  plug Amber::Pipe::CSRF.new
  plug AuthenticationPipe.new       # after session, before controller
end
```

### API with versioning and CORS
```crystal
pipeline :api do
  plug Amber::Pipe::Error.new
  plug Amber::Pipe::Logger.new
  plug Amber::Pipe::CORS.new(origins: ["https://myapp.com"], credentials: true)
  plug Amber::Pipe::ApiVersion.new(default_version: "v1")
  plug ApiTokenAuthPipe.new
end
```

### Behind a reverse proxy
```crystal
pipeline :web do
  plug Amber::Pipe::ClientIp.new("X-Forwarded-For")
  plug Amber::Pipe::Error.new
  plug Amber::Pipe::Logger.new
  # ... rest of pipeline
end
```

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/pipes/base.cr` | `Amber::Pipe::Base` — abstract pipe class |
| `src/amber/pipes/csrf.cr` | CSRF protection with PersistentToken/RefreshableToken |
| `src/amber/pipes/cors.cr` | CORS handling with Origin matching, preflight |
| `src/amber/pipes/logger.cr` | Request logging with filtering |
| `src/amber/pipes/session.cr` | Session persistence with sliding expiration |
| `src/amber/pipes/flash.cr` | Flash message persistence |
| `src/amber/pipes/error.cr` | Exception handling (404, 403, 500) |
| `src/amber/pipes/static.cr` | Static file serving |
| `src/amber/pipes/client_ip.cr` | Client IP extraction from proxy headers |
| `src/amber/pipes/api_version.cr` | API version header normalization |
| `src/amber/pipes/powered_by_amber.cr` | X-Powered-By header |
| `src/amber/pipes/controller.cr` | Final pipe — invokes controller action |
| `src/amber/dsl/server.cr` | `pipeline` and `routes` macros |
