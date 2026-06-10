# Amber V1 to V2 Migration Guide

This guide covers every breaking change between Amber V1 (1.4.x) and Amber V2, with before/after code examples and step-by-step migration instructions.

## Overview of Breaking Changes

| Change | Impact | Effort |
|--------|--------|--------|
| CLI removed | Project generation, scaffolding | Medium |
| Redis no longer bundled | Session/PubSub configuration | Low |
| YAML.mapping replaced | Any custom YAML types | Low |
| Kilt/Slang removed, ECR only | All templates | High |
| Database drivers removed | shard.yml changes | Low |
| Schema API added | New feature, opt-in | None (additive) |
| Import paths changed | Require statements | Low |
| Configuration restructured | YAML config files | Medium |
| Session security updated | Session configuration | Low |

## 1. CLI Removed

The `amber` CLI tool (generators, scaffolding, database commands, watch, routes, encrypt, exec) has been completely removed from the framework. Amber V2 is a library, not a CLI tool.

**Before (V1):**

```bash
amber new my_app
amber generate scaffold Post title:string body:text
amber db create migrate
amber watch
amber routes
```

**After (V2):**

```bash
# Create a project manually
mkdir my_app && cd my_app

# Create shard.yml with amber dependency
cat > shard.yml << 'YAML'
name: my_app
version: 0.1.0

dependencies:
  amber:
    github: amberframework/amber
    branch: v2-dev

crystal: ">= 1.0.0, < 2.0"
YAML

# Create the directory structure
mkdir -p src/controllers src/views/layouts config/environments

shards install

# Build and run directly
crystal build src/my_app.cr -o bin/my_app
./bin/my_app
```

A separate CLI tool (`amber_cli`) may be developed as an independent shard for project generation, but it is not part of the Amber framework itself.

## 2. Redis No Longer a Direct Dependency

Sessions and WebSocket pub/sub now use the adapter pattern. Memory adapters are the default and require no external services.

### shard.yml Changes

**Before (V1):**

```yaml
dependencies:
  amber:
    github: amberframework/amber
  redis:
    github: stefanwille/crystal-redis
```

**After (V2):**

```yaml
dependencies:
  amber:
    github: amberframework/amber
    branch: v2-dev
  # No redis dependency needed for default configuration
```

### Session Configuration

**Before (V1) -- `config/environments/development.yml`:**

```yaml
session:
  key: "my_app.session"
  store: redis
  redis_url: "redis://localhost:6379"
```

**After (V2) -- `config/environments/development.yml`:**

```yaml
session:
  key: "my_app.session"
  store: "signed_cookie"
  adapter: "memory"
  expires: 3600
```

### Continuing to Use Redis

If your application requires Redis for sessions or pub/sub (for example, in multi-server deployments), create a custom adapter and register it:

```crystal
class RedisSessionAdapter < Amber::Adapters::SessionAdapter
  def initialize(@redis : Redis::Client)
  end

  def get(session_id : String) : Hash(String, String)?
    data = @redis.get("session:#{session_id}")
    data ? Hash(String, String).from_json(data) : nil
  end

  def set(session_id : String, data : Hash(String, String), ttl : Int32 = 3600) : Nil
    @redis.setex("session:#{session_id}", ttl, data.to_json)
  end

  def delete(session_id : String) : Nil
    @redis.del("session:#{session_id}")
  end
end

# Register at startup
Amber::Adapters::AdapterFactory.register_session_adapter("redis") do
  RedisSessionAdapter.new(Redis::Client.new(url: ENV["REDIS_URL"]))
end
```

Then set your configuration to use it:

```yaml
session:
  adapter: "redis"
```

## 3. YAML.mapping Replaced with YAML::Serializable

This is a Crystal language change. The deprecated `YAML.mapping` macro has been replaced with the `YAML::Serializable` module.

**Before (V1):**

```crystal
class Settings
  YAML.mapping(
    name: String,
    port: Int32
  )
end
```

**After (V2):**

```crystal
class Settings
  include YAML::Serializable

  property name : String
  property port : Int32
end
```

All custom YAML-mapped types in your application need to be updated. The change is mechanical: replace `YAML.mapping(...)` with `include YAML::Serializable` and convert each field to a `property` declaration.

## 4. Template Engine Changes (Kilt/Slang Removed, ECR Only)

Amber V2 removes the `kilt` and `slang` dependencies. Templates use Crystal's built-in ECR (Embedded Crystal).

### Syntax Conversion

| Slang | ECR |
|-------|-----|
| `tag.class text` | `<tag class="class">text</tag>` |
| `= expression` | `<%= expression %>` |
| `- code` | `<% code %>` |
| `tag attr="val"` | `<tag attr="val"></tag>` |
| Indentation-based nesting | Explicit closing tags |

### Template Example

**Before (V1) -- Slang template (`show.slang`):**

```slang
h1 Welcome, #{@user.name}
p.description
  = @user.bio
- if @user.admin?
  span.badge Admin
```

**After (V2) -- ECR template (`show.ecr`):**

```ecr
<h1>Welcome, <%= @user.name %></h1>
<p class="description">
  <%= @user.bio %>
</p>
<% if @user.admin? %>
  <span class="badge">Admin</span>
<% end %>
```

### Form Conversion

**Before (V1) -- Slang form:**

```slang
form method="post" action="/users"
  .form-group
    label for="name" Name
    input.form-control type="text" name="name"
  button.btn type="submit" Create
```

**After (V2) -- ECR with V2 form helpers:**

```ecr
<%= form_for("/users", method: "POST") { %>
  <div class="form-group">
    <%= label("name") %>
    <%= text_field("name", class: "form-control") %>
  </div>
  <%= submit_button("Create", class: "btn") %>
<% } %>
```

### Render Macro Changes

**Before (V1):**

```crystal
render("show.slang")
render("show.slang", layout: "admin.slang")
```

**After (V2):**

```crystal
render("show.ecr")
render("show.ecr", layout: "admin.ecr")
```

### Layout Constant

**Before (V1):**

```crystal
class ApplicationController < Amber::Controller::Base
  LAYOUT = "application.slang"
end
```

**After (V2):**

```crystal
class ApplicationController < Amber::Controller::Base
  LAYOUT = "application.ecr"
end
```

### Migration Steps

1. Rename all `.slang` files to `.ecr`
2. Convert Slang syntax to ECR syntax using the conversion table above
3. Update all `render` calls to reference `.ecr` files
4. Update the `LAYOUT` constant in your ApplicationController to `"application.ecr"`
5. Test each template by visiting its route in the browser

## 5. Schema API for Type-Safe Params

The Schema API is **additive and backward compatible**. Existing `params["key"]` usage continues to work via the `SchemaParamsWrapper`. The Schema API provides opt-in type safety and validation for new code.

**Before (V1) -- raw params:**

```crystal
def create
  name = params["name"].to_s
  age = params["age"].to_s.to_i  # Crashes on invalid input
  email = params["email"].to_s

  # Manual validation
  if name.empty?
    flash[:error] = "Name is required"
    return redirect_to "/users/new"
  end

  user = User.create!(name: name, age: age, email: email)
  redirect_to "/users/#{user.id}"
end
```

**After (V2) -- Schema API:**

```crystal
class CreateUserSchema < Amber::Schema::Definition
  field :name, String, required: true
  field :age, Int32, required: true, min: 0, max: 150
  field :email, String, required: true, format: "email"
end

def create
  schema = CreateUserSchema.new(context.params.to_h)
  result = schema.validate

  if result.success?
    user = User.create!(
      name: schema.name.not_nil!,
      age: schema.age.not_nil!,
      email: schema.email.not_nil!
    )
    redirect_to "/users/#{user.id}"
  else
    flash[:error] = result.error_messages.join(", ")
    redirect_to "/users/new"
  end
end
```

The V1 `params["key"]` interface continues to work unchanged. The Schema API is opt-in per controller action. See the [Schema API Guide](guides/schema-api.md) for full documentation.

## 6. Database Drivers No Longer Bundled

Amber V1 bundled `pg`, `mysql`, and `sqlite3` as direct dependencies. V2 does not. Add only the database driver you need to your application's shard.yml.

**Before (V1) -- shard.yml:**

```yaml
dependencies:
  amber:
    github: amberframework/amber
  # pg, mysql, sqlite3 pulled in transitively by amber
```

**After (V2) -- shard.yml:**

```yaml
dependencies:
  amber:
    github: amberframework/amber
    branch: v2-dev
  pg:
    github: will/crystal-pg
  granite:
    github: amberframework/granite
  # Only include the driver(s) you actually use
```

## 7. Import Path Changes for Internalized Dependencies

The `amber_router` shard has been internalized into the framework. If your code directly referenced `amber_router` types, update the imports.

**Before (V1):**

```crystal
require "amber_router"
```

**After (V2):**

```crystal
# amber_router is now part of Amber itself; no separate require needed
require "amber"
```

Similarly, `backtracer` and `exception_page` are now internal to Amber. Remove any separate `require` statements for these libraries.

## 8. Configuration Changes

V2 uses typed configuration sections organized under a single `AppConfig` class, with support for environment variable overrides.

**Before (V1) -- flat YAML:**

```yaml
name: "my_app"
host: "0.0.0.0"
port: 3000
secret_key_base: "abc123"
redis_url: "redis://localhost:6379"
```

**After (V2) -- typed sections:**

```yaml
name: "my_app"

server:
  host: "0.0.0.0"
  port: 3000
  secret_key_base: "abc123"
  port_reuse: true
  process_count: 1
  ssl:
    key_file: null
    cert_file: null

database:
  url: "postgres://localhost/my_app_dev"

session:
  key: "my_app.session"
  store: "signed_cookie"
  adapter: "memory"
  expires: 3600

logging:
  severity: "debug"
  colorize: true

jobs:
  adapter: "memory"
  workers: 1
  auto_start: false

mailer:
  adapter: "memory"
  default_from: "noreply@example.com"
  smtp:
    host: "localhost"
    port: 587
    use_tls: true
```

### Environment Variable Overrides

Every configuration property can be overridden with an environment variable following the `AMBER_{SECTION}_{KEY}` naming convention:

```bash
AMBER_SERVER_PORT=8080
AMBER_SERVER_SECRET_KEY_BASE=my_secret
AMBER_DATABASE_URL=postgres://prod-host/my_app
AMBER_SESSION_ADAPTER=redis
AMBER_MAILER_ADAPTER=smtp
AMBER_MAILER_SMTP_HOST=smtp.example.com
```

Environment variables always take highest priority, overriding both YAML file values and compiled-in defaults.

### Server Configuration Block

**Before (V1):**

```crystal
Amber::Server.configure do |app|
  app.name = "My App"
  app.host = "0.0.0.0"
  app.port = 3000
end
```

**After (V2):**

```crystal
Amber::Server.configure do
  name = "My App"
  host = "0.0.0.0"
  port = 3000
end
```

The configure block no longer takes a block parameter. Properties are set directly.

## 9. Session Security Changes

V2 updates the default session configuration for improved security:

- Default store changed from `redis` to `signed_cookie`
- Session adapter defaults to `"memory"` (no external dependency)
- The `expires` field is an integer (seconds), defaulting to `0` (session cookie)

Review your session configuration and update as needed.

## Dependency Changes Summary

### Remove from shard.yml

- `redis` -- use adapter pattern instead
- `slang` -- use ECR templates
- `kilt` -- use ECR templates
- `micrate` -- handle migrations separately or add explicitly
- `pg` / `mysql` / `sqlite3` -- add only what you need at app level
- `compiled_license` -- removed

### Update in shard.yml

```yaml
dependencies:
  amber:
    github: amberframework/amber
    branch: v2-dev  # or version: ~> 2.0.0 once released
```

### Add to shard.yml (as needed)

```yaml
  # Database driver - pick one or more
  pg:
    github: will/crystal-pg

  # ORM - pick one
  granite:
    github: amberframework/granite
```

## Migration Checklist

- [ ] Update `shard.yml` to point to `amberframework/amber` (branch: v2-dev) and remove bundled dependencies
- [ ] Run `shards install`
- [ ] Replace `YAML.mapping` with `YAML::Serializable` in all custom types
- [ ] Rename all `.slang` templates to `.ecr` and convert syntax
- [ ] Update all `render` calls to reference `.ecr` files
- [ ] Update `LAYOUT` constant to `"application.ecr"`
- [ ] Restructure `config/environments/*.yml` files to use typed sections
- [ ] Update session configuration to use adapter pattern
- [ ] Remove any direct `require "redis"`, `require "amber_router"`, or `require "kilt"` statements
- [ ] Add database drivers explicitly to shard.yml if needed
- [ ] Test all routes and templates
- [ ] (Optional) Start migrating controller actions to use Schema API
