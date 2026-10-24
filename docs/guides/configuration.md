# Configuration

Amber V2 uses a typed configuration system organized into sections. Configuration is loaded from YAML files, with every value overridable via environment variables. Custom application configuration can be registered alongside the built-in sections.

## Quick Start

Create `config/environments/development.yml`:

```yaml
name: "my_app"

server:
  host: "localhost"
  port: 3000
  secret_key_base: "a_long_random_string_at_least_32_characters"

session:
  key: "my_app.session"
  store: "signed_cookie"
  adapter: "memory"

logging:
  severity: "debug"
  colorize: true
```

## Configuration Sections

### AppConfig (Top Level)

The `Amber::Configuration::AppConfig` class holds all configuration sections:

| Section | Class | Description |
|---------|-------|-------------|
| `name` | `String` | Application name (default: "Amber_App") |
| `server` | `ServerConfig` | HTTP server settings |
| `database` | `DatabaseConfig` | Database connection |
| `session` | `SessionConfig` | Session management |
| `pubsub` | `PubSubConfig` | WebSocket pub/sub |
| `logging` | `LoggingConfig` | Log output settings |
| `jobs` | `JobsConfig` | Background jobs |
| `mailer` | `MailerConfig` | Email delivery |
| `static` | `StaticConfig` | Static file serving |
| `secrets` | `Hash(String, String)` | Key-value secret storage |

### ServerConfig

```yaml
server:
  host: "0.0.0.0"             # Bind address (default: "localhost")
  port: 3000                   # Listen port (default: 3000)
  port_reuse: true             # Enable SO_REUSEPORT (default: true)
  process_count: 1             # Number of server processes (default: 1)
  secret_key_base: "..."       # Secret for session signing (required in production)
  ssl:
    key_file: "config/ssl/key.pem"   # SSL private key path
    cert_file: "config/ssl/cert.pem" # SSL certificate path
  trusted_proxies:             # Proxies allowed to report the client's scheme
    - "127.0.0.0/8"            # and address (default: loopback only)
    - "::1"
  unix_socket: null            # Listen on this UNIX socket path instead of host/port
```

#### Running behind a TLS-terminating proxy

When Caddy, nginx, a cloud load balancer, or a CDN terminates TLS and
forwards plain HTTP to Amber, the connection Amber sees is HTTP. Amber
decides whether a request is HTTPS with one method, `request.https?` (and
`request.scheme`), and everything that depends on the answer uses it,
including whether the cookie jar emits `Secure` cookies such as the session
and CSRF cookies.

`request.https?` is `true` when Amber terminates TLS itself (`server.ssl`),
or when the request's immediate peer matches an entry in
`server.trusted_proxies` and that proxy reported `https` through, in order:

1. the `proto=` parameter of the last element of `Forwarded` (RFC 7239),
2. the last value of `X-Forwarded-Proto`,
3. the CGI-style `HTTPS: on` header.

Each proxy appends its value to the end of these headers, so Amber reads the
last one, which is the value the trusted hop wrote. Requests from any other
peer keep their real scheme, whatever headers they carry.

Entries are IP addresses or CIDR blocks. Pick the list for your deployment:

| Deployment | `trusted_proxies` |
|------------|-------------------|
| Caddy or nginx on the same host, forwarding to `127.0.0.1` | default (loopback) |
| Proxy in another container or host on a private network | that network, e.g. `"10.0.0.0/8"` |
| Platform router that is the only route to the app (e.g. DigitalOcean App Platform) | the platform's internal range, or `"0.0.0.0/0"` and `"::/0"` when the app port is unreachable any other way |
| Cloudflare in front of a proxy on the host | default; let the local proxy pass Cloudflare's scheme through |

The same rule decides the client's IP address, `request.client_ip` (which
the `Amber::Pipe::ClientIp` pipe stores in `context.client_ip`). From an
untrusted peer it is the peer's own address, and forwarding headers are
ignored. From a trusted proxy Amber reads the hops in `Forwarded: for=` (or,
without that header, `X-Forwarded-For`) from the right, skips every hop that
is itself a trusted proxy, and returns the first one that is not; a spoofed
leftmost entry is never reached. A hop that is not an IP address ends the
walk, and the nearest verified address is used. `ClientIp.new(["CF-Connecting-IP"])`
reads a named header instead, under the same rule.

To put the proxy on a UNIX socket instead of loopback TCP, set
`server.unix_socket` (for Caddy, `reverse_proxy unix//run/app.sock`). While
it is set, every UNIX socket peer counts as a trusted proxy: the connection
is local by construction and the socket file's permissions decide who may
open it. A leftover socket file from a previous run is replaced at boot. It
cannot be combined with `server.ssl` or a `process_count` above 1.

Set the list in YAML, in `config/settings.cr`
(`settings.server.trusted_proxies = ["127.0.0.1", "10.0.0.0/8"]`), or with
the comma-separated `AMBER_SERVER_TRUSTED_PROXIES` environment variable. An
empty value trusts no proxy.

Validation rules:
- `port` must be between 1 and 65535
- `process_count` must be at least 1
- `secret_key_base` must be set in production
- `secret_key_base` should be at least 32 characters when set
- SSL files must exist when SSL is enabled
- every `trusted_proxies` entry must be an IP address or CIDR block
- `unix_socket` cannot be combined with `ssl` or a `process_count` above 1

### SessionConfig

```yaml
session:
  key: "amber.session"         # Cookie name (default: "amber.session")
  store: "signed_cookie"       # Store type (default: "signed_cookie")
  expires: 3600                # Session TTL in seconds (default: 0 = session cookie)
  adapter: "memory"            # Backend adapter (default: "memory")
```

Valid `store` values: `"signed_cookie"`, `"encrypted_cookie"`, `"redis"`

### DatabaseConfig

```yaml
database:
  url: "postgres://localhost/my_app_development"
```

### LoggingConfig

```yaml
logging:
  severity: "debug"            # Log level (default: "debug")
  colorize: true               # Color output (default: true)
  color: "light_cyan"          # Log color
```

### JobsConfig

```yaml
jobs:
  adapter: "memory"            # Queue backend (default: "memory")
  workers: 2                   # Number of worker fibers (default: 1)
  work_stealing: false         # Enable idle-server processing (default: false)
  polling_interval_seconds: 1.0  # Worker poll interval (default: 1.0)
  scheduler_interval_seconds: 5.0  # Scheduler interval (default: 5.0)
  auto_start: false            # Auto-start on server boot (default: false)
```

### MailerConfig

```yaml
mailer:
  adapter: "memory"            # Delivery backend (default: "memory")
  default_from: "noreply@example.com"
  smtp:
    host: "smtp.example.com"
    port: 587
    username: "user@example.com"
    password: "secret"
    use_tls: true
    helo_domain: "example.com"
```

### PubSubConfig

```yaml
pubsub:
  adapter: "memory"            # PubSub backend (default: "memory")
```

### StaticConfig

```yaml
static:
  headers:
    Cache-Control: "public, max-age=3600"
```

`Amber::Pipe::Static` applies these headers to existing static files. A
fingerprinted filename such as
`app-0123456789abcdef0123456789abcdef.css` always receives
`Cache-Control: public, max-age=31536000, immutable`; an unfingerprinted file
uses the configured policy, or `no-cache` when no policy is configured. Amber
also returns `X-Content-Type-Options: nosniff` and `Vary: Accept-Encoding`.

Put build-authored CSS, JavaScript, images, fonts, and downloads under
`app/assets/`, compile them to `public/assets/`, and resolve them through the
asset manifest. Keep user uploads on a separate persistent-storage lifecycle.

## Environment Variable Overrides

Every configuration property can be overridden with an environment variable. Environment variables always take highest priority, overriding both YAML file values and compiled-in defaults.

The naming convention is `AMBER_{SECTION}_{KEY}`:

| Environment Variable | Config Property |
|---------------------|----------------|
| `AMBER_NAME` | `name` |
| `AMBER_SERVER_HOST` | `server.host` |
| `AMBER_SERVER_PORT` | `server.port` |
| `AMBER_SERVER_PORT_REUSE` | `server.port_reuse` |
| `AMBER_SERVER_PROCESS_COUNT` | `server.process_count` |
| `AMBER_SERVER_SECRET_KEY_BASE` | `server.secret_key_base` |
| `AMBER_SERVER_SSL_KEY_FILE` | `server.ssl.key_file` |
| `AMBER_SERVER_SSL_CERT_FILE` | `server.ssl.cert_file` |
| `AMBER_SERVER_TRUSTED_PROXIES` | `server.trusted_proxies` (comma-separated) |
| `AMBER_SERVER_UNIX_SOCKET` | `server.unix_socket` |
| `AMBER_DATABASE_URL` or `DATABASE_URL` | `database.url` |
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

Boolean environment variables accept `"true"`, `"1"`, `"yes"` (case-insensitive) as true. All other values are treated as false.

## Custom Configuration Sections

Register custom configuration types to add application-specific settings that load from YAML and support environment variable overrides.

### Defining a Custom Config

```crystal
struct StripeConfig
  include YAML::Serializable

  property api_key : String = ""
  property webhook_secret : String = ""
  property currency : String = "usd"

  def initialize
  end
end

# Register with Amber's configuration system
Amber::Configuration.register(:stripe, StripeConfig)
```

### YAML Configuration

Add your custom section to the environment YAML file:

```yaml
name: "my_app"

server:
  port: 3000

stripe:
  api_key: "sk_test_..."
  webhook_secret: "whsec_..."
  currency: "usd"
```

### Accessing Custom Config

```crystal
stripe = Amber.settings.custom(:stripe, StripeConfig)
stripe.api_key          # => "sk_test_..."
stripe.webhook_secret   # => "whsec_..."
stripe.currency         # => "usd"
```

## Configuration Validation

All configuration sections include built-in validation. Call `validate!` to check all settings at startup:

```crystal
config = Amber::Configuration::AppConfig.from_yaml(File.read("config/environments/production.yml"))
config.validate!(Amber::Environment::Env.new("production"))
# Raises Amber::Exceptions::ConfigurationError if any validation fails
```

Validation checks include:
- Port range (1-65535)
- Process count (>= 1)
- Secret key base required in production
- Secret key base minimum length (32 characters)
- SSL file existence when SSL is enabled
- Valid session store type
- Valid logging severity level

## Configuration Priority

Configuration values are resolved in this order (highest priority first):

1. **Environment variables** (`AMBER_SERVER_PORT=8080`)
2. **Environment YAML file** (`config/environments/production.yml`)
3. **Compiled defaults** (hardcoded in the config classes)

## Full Example

A complete `config/environments/production.yml`:

```yaml
name: "my_app"

server:
  host: "0.0.0.0"
  port: 3000
  port_reuse: true
  process_count: 4
  secret_key_base: "use_a_strong_random_string_here_at_least_32_chars"
  ssl:
    key_file: "/etc/ssl/private/app.key"
    cert_file: "/etc/ssl/certs/app.crt"

database:
  url: "postgres://user:pass@db-host/my_app_production"

session:
  key: "my_app.session"
  store: "encrypted_cookie"
  adapter: "memory"
  expires: 86400

pubsub:
  adapter: "memory"

logging:
  severity: "info"
  colorize: false

jobs:
  adapter: "memory"
  workers: 4
  auto_start: true
  polling_interval_seconds: 0.5
  work_stealing: true

mailer:
  adapter: "smtp"
  default_from: "noreply@myapp.com"
  smtp:
    host: "smtp.sendgrid.net"
    port: 587
    username: "apikey"
    password: "SG.xxxxx"
    use_tls: true
    helo_domain: "myapp.com"

secrets:
  api_key: "secret_api_key_here"
```

## Source Files

- `src/amber/configuration.cr` -- Requires all configuration files
- `src/amber/configuration/app_config.cr` -- Top-level AppConfig with validation
- `src/amber/configuration/server_config.cr` -- ServerConfig and SSLConfig
- `src/amber/configuration/database_config.cr` -- DatabaseConfig
- `src/amber/configuration/session_config.cr` -- SessionConfig
- `src/amber/configuration/pubsub_config.cr` -- PubSubConfig
- `src/amber/configuration/logging_config.cr` -- LoggingConfig
- `src/amber/configuration/jobs_config.cr` -- JobsConfig
- `src/amber/configuration/mailer_config.cr` -- MailerConfig
- `src/amber/configuration/static_config.cr` -- StaticConfig
- `src/amber/configuration/env_override.cr` -- Environment variable override logic
- `src/amber/configuration/custom_registry.cr` -- Custom config registration
