# Changelog

## 2.0.0-dev (unreleased)

This release represents a major architectural revision of the Amber framework.
The primary goals were to remove all runtime dependencies, modernize the
Crystal language patterns in use, and add first-class support for background
jobs, email, and typed configuration. The CLI has been extracted to a separate
repository.

### Breaking Changes

#### CLI removed from framework

The `amber` CLI tool — generators, scaffolding, database commands, `amber
watch`, `amber routes`, `amber encrypt`, `amber exec` — has been removed from
this repository. Amber V2 is a library shard, not a CLI tool.

A replacement CLI is maintained as a separate project:
https://github.com/amberframework/amber_cli

#### Zero runtime dependencies

All runtime shards have been removed from `shard.yml`. The following were
either dropped or internalized:

| Dependency | Disposition |
|---|---|
| `redis` / `crystal-redis` | Replaced by adapter pattern; memory adapter is default |
| `amber_router` | Internalized into `src/amber/router/engine/` |
| `backtracer` | Internalized into `src/amber/` |
| `exception_page` | Internalized into `src/amber/` |
| `kilt` | Removed; ECR only |
| `slang` | Removed; ECR only |
| `pg` / `mysql` / `sqlite3` | Removed; add the driver you need at app level |
| `compiled_license` | Removed |
| `micrate` | Removed; handle migrations at app level |

The only remaining dependency is `ameba` (development only) for linting.

#### Template engine: ECR only

Kilt and Slang have been removed. Templates must use Crystal's built-in ECR
(Embedded Crystal). Rename `.slang` files to `.ecr` and convert syntax
accordingly. See [docs/migration-guide.md](docs/migration-guide.md) for a
conversion table.

#### YAML.mapping replaced with YAML::Serializable

The deprecated `YAML.mapping` macro no longer works in Crystal 1.x. All
framework internals have been updated to `include YAML::Serializable`. Any
application code using `YAML.mapping` must be updated; the change is
mechanical (see migration guide).

#### Configuration restructured

The flat YAML configuration format has been replaced with typed, sectioned
configuration structs. Sections: `server`, `database`, `session`, `logging`,
`jobs`, `mailer`. Every property can be overridden with an environment variable
using the `AMBER_{SECTION}_{KEY}` naming convention (e.g.,
`AMBER_SERVER_PORT=8080`, `AMBER_DATABASE_URL=postgres://...`).

The `Amber::Server.configure` block no longer accepts a block parameter;
properties are set directly inside the block.

#### Session defaults changed

Default session store changed from `redis` to `signed_cookie`. Default adapter
is `memory` (no external service required). The `expires` field is an integer
(seconds).

### New Features

#### Schema API

A type-safe request validation and coercion layer. Define a schema class with
typed fields and validators (required, length, format, range, pattern, enum).
Parsers handle JSON, multipart, query string, and XML bodies. Existing
`params["key"]` usage continues to work unchanged via `SchemaParamsWrapper`;
the Schema API is opt-in per action.

See [docs/guides/schema-api.md](docs/guides/schema-api.md).

#### Typed configuration with environment variable overrides

`Amber::Configuration::AppConfig` holds all framework settings as typed Crystal
structs. Any field can be overridden at runtime via environment variables
following the `AMBER_{SECTION}_{KEY}` pattern without changing YAML files.
Custom configuration sections can be registered in the same registry.

See [docs/guides/configuration.md](docs/guides/configuration.md).

#### Built-in background jobs

A work-stealing job queue that runs inside idle web workers — no separate
process required. Includes retry logic and a pluggable adapter interface (memory
adapter ships by default). Redis and other backends can be added via custom
adapters.

See [docs/guides/background-jobs.md](docs/guides/background-jobs.md).

#### Built-in mailer

Fluent API for composing and sending email. Ships with an SMTP adapter and a
memory adapter for testing. The memory adapter records sent mail so tests can
assert on it without a real mail server.

See [docs/guides/mailer.md](docs/guides/mailer.md).

#### WebSocket modernization

- Message decoders: plug in a decoder to parse incoming frames into typed
  messages before they reach your channel handler
- Presence tracking: built-in presence API that tracks which users are
  connected and broadcasts join/leave events
- Connection recovery: automatic reconnect with exponential backoff and
  last-message-id replay
- Improved error handling and channel lifecycle callbacks

See [docs/guides/websockets.md](docs/guides/websockets.md).

#### Named routes, constraints, and API versioning

- `route_url(:route_name, param: value)` — generate URLs by name rather than
  hardcoded strings
- Route constraints: host, subdomain, format, and custom lambda constraints
- API versioning middleware (`ApiVersion` pipe) with header- and
  URL-segment-based version detection
- Route introspection: list all registered routes with names, methods, and
  paths at runtime

See [docs/guides/routing.md](docs/guides/routing.md).

#### Built-in markdown renderer

A GFM-compatible Markdown renderer with autolinks, footnotes, table-of-contents
generation, and syntax highlighting hooks. No external dependency.

See [docs/guides/markdown.md](docs/guides/markdown.md).

#### Action helpers

Helper methods for views: form builders, URL helpers, asset helpers, text
formatting, and number formatting.

See [docs/guides/action-helpers.md](docs/guides/action-helpers.md).

#### Built-in test framework

`Amber::Testing::ContextBuilder` simulates HTTP requests against your
controllers without starting a real server. Includes WebSocket test helpers and
assertion methods for response status, headers, body content, and redirects.

See [docs/guides/testing.md](docs/guides/testing.md).

#### Session security improvements

`MessageEncryptor` and `MessageVerifier` updated to SHA-256. SameSite cookie
attribute support. Key rotation support. Session regeneration on privilege
escalation.

### Adapter Pattern

Sessions, PubSub, jobs, and mailer now all use a pluggable adapter interface.
The `AdapterFactory` allows registering custom backends at startup. This is the
supported path for adding Redis sessions, Redis pub/sub, or any other backend
without coupling the framework to a specific shard.

### Documentation

A full documentation suite has been added under `docs/`:

- [Migration guide](docs/migration-guide.md) — complete V1 to V2 upgrade instructions
- [Schema API guide](docs/guides/schema-api.md)
- [Configuration guide](docs/guides/configuration.md)
- [Routing guide](docs/guides/routing.md) (named routes, constraints, API versioning)
- [WebSocket guide](docs/guides/websockets.md)
- [Background jobs guide](docs/guides/background-jobs.md)
- [Mailer guide](docs/guides/mailer.md)
- [Testing guide](docs/guides/testing.md)
- [Markdown guide](docs/guides/markdown.md)
- [Action helpers guide](docs/guides/action-helpers.md)
- [LSP setup guide](docs/guides/lsp-setup.md) (Claude Code integration)

---

For changes prior to V2, see the git log at
https://github.com/amberframework/amber/commits/master
