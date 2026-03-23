---
name: amber-controllers
description: Amber V2 controller lifecycle — base class, filters, helpers, rendering, redirects, params, flash, cookies, sessions, CSRF, respond_with
user-invocable: false
---

# Amber Controllers

Controllers handle HTTP requests by inheriting from `Amber::Controller::Base`. They receive a context, run before/after filters, execute an action method, and return a response.

## Controller Base Class

```crystal
class PostsController < Amber::Controller::Base
  def index
    render("index.ecr")
  end

  def show
    render("show.ecr")
  end

  def create
    redirect_to action: :index
  end
end
```

### Included Modules

`Amber::Controller::Base` includes these helper modules automatically:

| Module | Provides |
|--------|----------|
| `Helpers::CSRF` | `csrf_token`, `csrf_tag`, `csrf_metatag` |
| `Helpers::Redirect` | `redirect_to`, `redirect_back` |
| `Helpers::Render` | `render` macro |
| `Helpers::Responders` | `respond_with`, `set_response` |
| `Helpers::Route` | `action_name`, `route_resource`, `route_scope`, `controller_name` |
| `Helpers::I18n` | Internationalization helpers |
| `Helpers::TagHelpers` | HTML tag generation helpers |
| `Helpers::TextHelpers` | Text formatting helpers |
| `Helpers::NumberHelpers` | Number formatting helpers |
| `Helpers::FormHelpers` | Form building helpers |
| `Helpers::URLHelpers` | URL generation helpers |
| `Helpers::AssetHelpers` | Asset path/URL helpers |
| `Helpers::MarkdownHelper` | Markdown rendering in views |
| `Callbacks` | `before_action`, `after_action` filters |

### Delegated Methods from Context

These methods are delegated directly to the HTTP context:

```crystal
client_ip, cookies, delete?, flash, format, get?, halt!, head?,
patch?, port, post?, put?, request, requested_url, response,
route, session, valve, websocket?
```

Source: `src/amber/controller/base.cr`

## Before/After Filters

Filters run code before or after controller actions. Defined using `before_action` and `after_action` macros.

```crystal
class PostsController < Amber::Controller::Base
  # Run for ALL actions
  before_action do
    all { authenticate_user }
  end

  # Run for specific actions only
  before_action do
    only(:edit, :update, :destroy) { authorize_post }
    only(:show) { load_post }
  end

  # Run for all EXCEPT specific actions
  before_action do
    except(:index) { find_post }
  end

  # After filters work the same way
  after_action do
    all { log_access }
  end
end
```

**Filter methods:**
- `all { block }` — runs for every action
- `only(action, &block)` or `only(actions_array, &block)` — runs only for specified actions
- `except(action, &block)` or `except(actions_array, &block)` — runs for all except specified actions

Source: `src/amber/controller/filters.cr`, `src/amber/dsl/callbacks.cr`

## Rendering

The `render` macro compiles ECR templates at compile time.

```crystal
# Renders src/views/posts/index.ecr with layout
render("index.ecr")

# Renders without layout
render("index.ecr", layout: false)

# Renders with a custom layout
render("index.ecr", layout: "admin.ecr")

# Renders a partial (no layout)
render(partial: "post_item.ecr")

# Renders from a specific path
render("index.ecr", path: "src/views")

# Full path template
render("posts/index.ecr")
```

**Convention:** Template path is inferred from the controller name. `PostsController` looks in `src/views/posts/`. Layout defaults to `src/views/layouts/application.ecr`.

**Layout constant:** Override the default layout per controller:
```crystal
class AdminController < Amber::Controller::Base
  LAYOUT = "admin.ecr"  # Uses src/views/layouts/admin.ecr
end
```

Set `LAYOUT = "false"` to disable layout for all actions in a controller.

Source: `src/amber/controller/helpers/render.cr`

## Content Negotiation (respond_with)

`respond_with` selects the response format based on the `Accept` header or URL extension.

```crystal
def show
  post = find_post(params[:id])
  respond_with do
    html render("show.ecr")
    json post.to_json
    xml post.to_xml
    text post.title
  end
end

# With custom status code
def create
  respond_with(201) do
    json({id: post.id}.to_json)
    html render("show.ecr")
  end
end
```

**Supported formats:** `html`, `json`, `xml`, `text`, `js`

If no matching format is found, returns 406 Not Acceptable.

Source: `src/amber/controller/helpers/responders.cr`

## Redirects

```crystal
# Redirect to a URL string
redirect_to "/posts"

# Redirect to a controller action
redirect_to action: :index

# Redirect to another controller's action
redirect_to controller: :posts, action: :index
redirect_to controller: PostsController, action: :show

# With status code
redirect_to "/posts", status: 301

# With query params
redirect_to action: :index, params: {"page" => "2"}

# With flash message
redirect_to action: :index, flash: {"success" => "Post created!"}

# Redirect back to referer
redirect_back
```

Source: `src/amber/controller/helpers/redirect.cr`

## Params

Access request parameters (query string, form data, route params):

```crystal
params[:id]        # Raises if missing
params[:id]?       # Returns nil if missing
params.fetch_all   # All params as Hash
```

## Halt

Stop request processing immediately:

```crystal
halt!(403, "Forbidden")
```

## Flash Messages

Flash messages persist for one request (stored in session):

```crystal
# Set flash
flash["notice"] = "Post saved successfully"
flash["alert"] = "Something went wrong"

# Read flash (in template or next request)
flash["notice"]?

# Merge flash during redirect
redirect_to action: :index, flash: {"notice" => "Done!"}
```

## Cookies

```crystal
# Set a cookie
cookies["user_pref"] = "dark_mode"

# Read a cookie
cookies["user_pref"]?

# Cookies are written to response headers automatically
```

## Sessions

```crystal
# Set session value
session["user_id"] = user.id.to_s

# Read session value
session["user_id"]?

# Delete session value
session.delete("user_id")
```

## CSRF Protection

In controllers:
```crystal
csrf_token       # Returns the current CSRF token string
csrf_tag         # Returns hidden input HTML: <input type="hidden" name="_csrf" value="..." />
csrf_metatag     # Returns meta tag HTML: <meta name="_csrf" content="..." />
```

In ECR templates:
```ecr
<form method="post">
  <%= csrf_tag %>
  <!-- form fields -->
</form>
```

Source: `src/amber/controller/helpers/csrf.cr`

## Named Route Helpers

Generate paths and URLs for named routes:

```crystal
# Path helper (e.g., "/posts/123")
route_path(:post, id: 123)

# Full URL helper (e.g., "https://example.com/posts/123")
route_url(:post, id: 123)
```

Source: `src/amber/controller/base.cr:57-63`

## Route Info Helpers

```crystal
action_name                # Current action name (e.g., :show)
route_resource             # Current route resource pattern
route_scope                # Current route scope
controller_name            # Controller name without "Controller" suffix, underscored
controller_name_no_underscore  # Same but without underscores
```

Source: `src/amber/controller/helpers/route.cr`

## Schema Integration

Controllers can integrate with the Schema API for request validation. See the schema-api skill for details.

Source: `src/amber/controller/schema_integration.cr`

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/controller/base.cr` | `Amber::Controller::Base` with all includes and delegates |
| `src/amber/controller/filters.cr` | Filter/callback system (Callbacks, Filters, FilterBuilder) |
| `src/amber/controller/helpers/render.cr` | `render` macro for ECR templates |
| `src/amber/controller/helpers/responders.cr` | `respond_with` content negotiation |
| `src/amber/controller/helpers/redirect.cr` | `redirect_to`, `redirect_back` |
| `src/amber/controller/helpers/csrf.cr` | `csrf_token`, `csrf_tag`, `csrf_metatag` |
| `src/amber/controller/helpers/route.cr` | `action_name`, `controller_name`, etc. |
| `src/amber/controller/helpers/i18n.cr` | Internationalization |
| `src/amber/controller/helpers/tag_helpers.cr` | HTML tag generation |
| `src/amber/controller/helpers/text_helpers.cr` | Text formatting |
| `src/amber/controller/helpers/number_helpers.cr` | Number formatting |
| `src/amber/controller/helpers/form_helpers.cr` | Form building |
| `src/amber/controller/helpers/url_helpers.cr` | URL generation |
| `src/amber/controller/helpers/asset_helpers.cr` | Asset path/URL helpers |
| `src/amber/controller/helpers/markdown.cr` | Markdown rendering in views |
| `src/amber/controller/error.cr` | Error controller for exception rendering |
| `src/amber/controller/static.cr` | Static file controller |
| `src/amber/controller/schema_integration.cr` | Schema API integration |
| `src/amber/dsl/callbacks.cr` | `before_action`, `after_action` macros |
