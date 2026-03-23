---
name: amber-configuration
description: Amber V2 typed configuration system — config structs, environment loading, env var overrides, validation, custom registry
user-invocable: false
---

# Amber Configuration

Amber V2 uses typed configuration structs loaded from YAML files, with environment variable overrides and validation.

## Accessing Configuration

```crystal
# Read any setting
Amber.settings.name             # => "MyApp"
Amber.settings.host             # => "localhost"
Amber.settings.port             # => 3000
Amber.settings.secret_key_base  # => "abc123..."

# V2 typed sub-config accessors
Amber.settings.server           # => ServerConfig
Amber.settings.database         # => DatabaseConfig
Amber.settings.mailer           # => MailerConfig
Amber.settings.static           # => StaticConfig
Amber.settings.secrets          # => Hash(String, String)
```

## Programmatic Configuration

Use `Amber::Server.configure` to set values in code:

```crystal
Amber::Server.configure do
  name "MyApp"
  host "0.0.0.0"
  port 8080
  secret_key_base "a-long-random-secret-at-least-32-chars"
end
```

## Environment Detection

Amber reads `AMBER_ENV` (defaults to `"development"`):

```crystal
Amber.env                  # => Env instance
Amber.env.development?     # => true
Amber.env.production?      # => false
Amber.env.test?            # => false
Amber.env == "staging"     # => true/false
Amber.env.in?("development", "test")  # => true/false
```

Set the environment:

```crystal
Amber.env = "production"
```

Or via the shell:

```bash
AMBER_ENV=production crystal run src/app.cr
```

## YAML Configuration Files

Config files live in `config/environments/` and are named by environment:

```
config/environments/
  development.yml
  test.yml
  production.yml
```

Amber auto-detects V2 format when the YAML has a `server` key that is a mapping. A full V2 config file:

```yaml
name: MyApp

server:
  host: localhost
  port: 3000
  port_reuse: true
  process_count: 1
  secret_key_base: "your-secret-key-at-least-32-characters-long"
  ssl:
    key_file: null
    cert_file: null

database:
  url: "postgres://localhost:5432/myapp_development"

session:
  key: "amber.session"
  store: "signed_cookie"
  expires: 0
  adapter: "memory"

pubsub:
  adapter: "memory"

logging:
  severity: "debug"
  colorize: true
  color: "light_cyan"
  filter:
    - password
    - confirm_password
  skip: []

jobs:
  adapter: "memory"
  queues:
    - default
  workers: 1
  work_stealing: false
  polling_interval_seconds: 1.0
  scheduler_interval_seconds: 5.0
  auto_start: false

mailer:
  adapter: "memory"
  default_from: "noreply@example.com"
  smtp:
    host: "localhost"
    port: 587
    username: null
    password: null
    use_tls: true
    helo_domain: "localhost"

static:
  headers:
    Cache-Control: "public, max-age=604800"

secrets:
  api_key: "sk_test_abc123"
  webhook_secret: "whsec_xyz789"
```

Encrypted config files are also supported. Place a `.development.enc` file alongside (or instead of) the YAML file and Amber will decrypt it at load time via `Support::FileEncryptor`.

## Config Structs Reference

### AppConfig

The root configuration object. All sub-configs hang off this struct.

| Property | Type | Default |
|----------|------|---------|
| `name` | `String` | `"Amber_App"` |
| `server` | `ServerConfig` | `ServerConfig.new` |
| `database` | `DatabaseConfig` | `DatabaseConfig.new` |
| `session` | `SessionConfig` | `SessionConfig.new` |
| `pubsub` | `PubSubConfig` | `PubSubConfig.new` |
| `logging` | `LoggingConfig` | `LoggingConfig.new` |
| `jobs` | `JobsConfig` | `JobsConfig.new` |
| `mailer` | `MailerConfig` | `MailerConfig.new` |
| `static` | `StaticConfig` | `StaticConfig.new` |
| `secrets` | `Hash(String, String)` | `{}` |

### ServerConfig

| Property | Type | Default |
|----------|------|---------|
| `host` | `String` | `"localhost"` |
| `port` | `Int32` | `3000` |
| `port_reuse` | `Bool` | `true` |
| `process_count` | `Int32` | `1` |
| `secret_key_base` | `String` | `""` |
| `ssl` | `SSLConfig` | `SSLConfig.new` |

### SSLConfig

Nested under `server.ssl`.

| Property | Type | Default |
|----------|------|---------|
| `key_file` | `String?` | `nil` |
| `cert_file` | `String?` | `nil` |

SSL is enabled when both `key_file` and `cert_file` are non-nil. Call `ssl.is_enabled?` to check.

### DatabaseConfig

| Property | Type | Default |
|----------|------|---------|
| `url` | `String` | `""` |

### SessionConfig

| Property | Type | Default |
|----------|------|---------|
| `key` | `String` | `"amber.session"` |
| `store` | `String` | `"signed_cookie"` |
| `expires` | `Int32` | `0` |
| `adapter` | `String` | `"memory"` |

Valid `store` values: `"signed_cookie"`, `"encrypted_cookie"`, `"redis"`.

### PubSubConfig

| Property | Type | Default |
|----------|------|---------|
| `adapter` | `String` | `"memory"` |

### LoggingConfig

| Property | Type | Default |
|----------|------|---------|
| `severity` | `String` | `"debug"` |
| `colorize` | `Bool` | `true` |
| `color` | `String` | `"light_cyan"` |
| `filter` | `Array(String)` | `["password", "confirm_password"]` |
| `skip` | `Array(String)` | `[]` |

Valid `severity` values: `"trace"`, `"debug"`, `"info"`, `"notice"`, `"warn"`, `"error"`, `"fatal"`, `"none"`.

Valid `color` values: `"black"`, `"red"`, `"green"`, `"yellow"`, `"blue"`, `"magenta"`, `"cyan"`, `"light_gray"`, `"dark_gray"`, `"light_red"`, `"light_green"`, `"light_yellow"`, `"light_blue"`, `"light_magenta"`, `"light_cyan"`, `"white"`.

### JobsConfig

| Property | Type | Default |
|----------|------|---------|
| `adapter` | `String` | `"memory"` |
| `queues` | `Array(String)` | `["default"]` |
| `workers` | `Int32` | `1` |
| `work_stealing` | `Bool` | `false` |
| `polling_interval_seconds` | `Float64` | `1.0` |
| `scheduler_interval_seconds` | `Float64` | `5.0` |
| `auto_start` | `Bool` | `false` |

Convenience methods: `polling_interval` and `scheduler_interval` return `Time::Span` values.

### MailerConfig

| Property | Type | Default |
|----------|------|---------|
| `adapter` | `String` | `"memory"` |
| `default_from` | `String` | `"noreply@example.com"` |
| `smtp` | `SMTPConfig` | `SMTPConfig.new` |

Valid `adapter` values: `"memory"`, `"smtp"`.

### SMTPConfig

Nested under `mailer.smtp`.

| Property | Type | Default |
|----------|------|---------|
| `host` | `String` | `"localhost"` |
| `port` | `Int32` | `587` |
| `username` | `String?` | `nil` |
| `password` | `String?` | `nil` |
| `use_tls` | `Bool` | `true` |
| `helo_domain` | `String` | `"localhost"` |

### StaticConfig

| Property | Type | Default |
|----------|------|---------|
| `headers` | `Hash(String, String)` | `{}` |

## Environment Variable Overrides

Environment variables override YAML values and compiled-in defaults. They follow the pattern `AMBER_{SECTION}_{KEY}`:

### All Supported Variables

| Variable | Maps To |
|----------|---------|
| `AMBER_NAME` | `name` |
| `AMBER_SERVER_HOST` | `server.host` |
| `AMBER_SERVER_PORT` | `server.port` |
| `AMBER_SERVER_PORT_REUSE` | `server.port_reuse` |
| `AMBER_SERVER_PROCESS_COUNT` | `server.process_count` |
| `AMBER_SERVER_SECRET_KEY_BASE` | `server.secret_key_base` |
| `AMBER_SERVER_SSL_KEY_FILE` | `server.ssl.key_file` |
| `AMBER_SERVER_SSL_CERT_FILE` | `server.ssl.cert_file` |
| `AMBER_DATABASE_URL` | `database.url` |
| `AMBER_SESSION_KEY` | `session.key` |
| `AMBER_SESSION_STORE` | `session.store` |
| `AMBER_SESSION_EXPIRES` | `session.expires` |
| `AMBER_SESSION_ADAPTER` | `session.adapter` |
| `AMBER_PUBSUB_ADAPTER` | `pubsub.adapter` |
| `AMBER_LOGGING_SEVERITY` | `logging.severity` |
| `AMBER_LOGGING_COLORIZE` | `logging.colorize` |
| `AMBER_LOGGING_COLOR` | `logging.color` |
| `AMBER_JOBS_ADAPTER` | `jobs.adapter` |
| `AMBER_JOBS_WORKERS` | `jobs.workers` |
| `AMBER_JOBS_WORK_STEALING` | `jobs.work_stealing` |
| `AMBER_JOBS_POLLING_INTERVAL_SECONDS` | `jobs.polling_interval_seconds` |
| `AMBER_JOBS_SCHEDULER_INTERVAL_SECONDS` | `jobs.scheduler_interval_seconds` |
| `AMBER_JOBS_AUTO_START` | `jobs.auto_start` |
| `AMBER_MAILER_ADAPTER` | `mailer.adapter` |
| `AMBER_MAILER_DEFAULT_FROM` | `mailer.default_from` |
| `AMBER_MAILER_SMTP_HOST` | `mailer.smtp.host` |
| `AMBER_MAILER_SMTP_PORT` | `mailer.smtp.port` |
| `AMBER_MAILER_SMTP_USERNAME` | `mailer.smtp.username` |
| `AMBER_MAILER_SMTP_PASSWORD` | `mailer.smtp.password` |
| `AMBER_MAILER_SMTP_USE_TLS` | `mailer.smtp.use_tls` |
| `AMBER_MAILER_SMTP_HELO_DOMAIN` | `mailer.smtp.helo_domain` |

Boolean variables accept `"true"`, `"1"`, or `"yes"` (case-insensitive) as truthy. Everything else is false.

Priority order (highest to lowest):
1. Environment variables
2. YAML file values
3. Compiled-in struct defaults

## Configuration Validation

Call `validate!` on the `AppConfig` to check all sub-configs at once. Validation collects errors from every section and raises a single `Amber::Exceptions::ConfigurationError` with the full list:

```crystal
config = Amber.settings.to_app_config
config.validate!(Amber.env)
```

### Validation Rules

**ServerConfig:**
- `port` must be between 1 and 65535
- `process_count` must be at least 1
- `secret_key_base` must be set in production
- `secret_key_base` must be at least 32 characters when set
- SSL files must exist on disk when SSL is enabled

**SessionConfig:**
- `store` must be one of: `"signed_cookie"`, `"encrypted_cookie"`, `"redis"`

**LoggingConfig:**
- `severity` must be one of: `"trace"`, `"debug"`, `"info"`, `"notice"`, `"warn"`, `"error"`, `"fatal"`, `"none"`

**JobsConfig:**
- `workers` must be at least 1
- `polling_interval_seconds` must be positive
- `scheduler_interval_seconds` must be positive

**MailerConfig (when adapter is "smtp"):**
- `smtp.host` must be set
- `smtp.port` must be between 1 and 65535

## Secrets Hash

The `secrets` hash stores arbitrary key-value pairs for API keys, tokens, and other sensitive values:

```yaml
secrets:
  stripe_key: "sk_test_abc123"
  github_token: "ghp_xyz789"
```

Access in code:

```crystal
Amber.settings.secrets["stripe_key"]  # => "sk_test_abc123"
```

For production, use encrypted config files (`.production.enc`) to avoid committing secrets to source control.

## Custom Config Registry

Register your own typed config sections that load from the same YAML file.

### 1. Define a config struct

```crystal
struct MyApp::StripeConfig
  include YAML::Serializable

  property api_key : String = ""
  property webhook_secret : String = ""
  property is_live_mode : Bool = false

  def initialize
  end
end
```

### 2. Register before the app boots

```crystal
Amber::Configuration.register(:stripe, MyApp::StripeConfig)
```

### 3. Add the section to your YAML

```yaml
name: MyApp

server:
  host: localhost
  port: 3000

stripe:
  api_key: "sk_test_abc123"
  webhook_secret: "whsec_xyz789"
  is_live_mode: false
```

### 4. Access the config

```crystal
stripe = Amber.settings.custom(:stripe, MyApp::StripeConfig)
stripe.api_key        # => "sk_test_abc123"
stripe.is_live_mode   # => false
```

If the YAML file has no matching section, the default instance (from the struct's defaults) is returned.

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/configuration.cr` | Requires all config sub-modules |
| `src/amber/configuration/app_config.cr` | `AppConfig` root struct, `validate!`, `custom` accessor |
| `src/amber/configuration/server_config.cr` | `ServerConfig`, `SSLConfig` |
| `src/amber/configuration/database_config.cr` | `DatabaseConfig` |
| `src/amber/configuration/session_config.cr` | `SessionConfig` with `store_type` helper |
| `src/amber/configuration/pubsub_config.cr` | `PubSubConfig` |
| `src/amber/configuration/logging_config.cr` | `LoggingConfig` with `severity_level`, `color_symbol` |
| `src/amber/configuration/jobs_config.cr` | `JobsConfig` with `polling_interval`, `scheduler_interval` |
| `src/amber/configuration/mailer_config.cr` | `MailerConfig`, `SMTPConfig` |
| `src/amber/configuration/static_config.cr` | `StaticConfig` |
| `src/amber/configuration/env_override.cr` | `EnvOverride.apply_all` — environment variable mapping |
| `src/amber/configuration/custom_registry.cr` | `register` macro, `load_custom_from_yaml` |
| `src/amber/environment.cr` | `Environment` module — `settings`, `env` class accessors |
| `src/amber/environment/env.cr` | `Env` class — environment name, dynamic `?` methods |
| `src/amber/environment/loader.cr` | `Loader` — YAML loading, V1/V2 format detection |
| `src/amber/environment/settings.cr` | `Settings` — V1 properties, V2 subsection accessors, `to_app_config` |
| `src/amber/server/server.cr` | `Amber::Server.configure` block |
