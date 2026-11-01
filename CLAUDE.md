# CLAUDE.md

## Project Overview

Amber V2 is a web application framework written in Crystal. It provides an efficient, cohesive framework that embraces Crystal's language philosophies with near-zero runtime dependencies.

**Version**: 2.0.0-dev
**Crystal**: >= 1.0.0, < 2.0
**License**: MIT
**Dependencies**: ameba (dev only) — framework is entirely self-contained at runtime

## Development Commands

```bash
# Install dependencies (ameba only)
shards install

# Run all tests and checks (recommended)
./bin/amber_spec

# Individual commands
crystal spec                   # Run test suite
crystal spec spec/amber/controller/base_spec.cr  # Single file
crystal tool format --check    # Check formatting
crystal tool format            # Auto-format
./bin/ameba                    # Run linter
crystal docs                   # Generate API docs → docs/
```

## Architecture Overview

### Core Subsystems

1. **Controllers** (`src/amber/controller/`): Base controller with before/after filters, rendering, redirects, CSRF helpers, route helpers, responders, i18n

2. **Router** (`src/amber/router/`): HTTP routing with params, cookies, sessions, flash messages, file uploads. V2 adds named routes, constraints (host, subdomain, format, custom), and API versioning

3. **Router Engine** (`src/amber/router/engine/`): Internalized radix-tree router (formerly amber_router shard). Segment-based matching with fixed, variable, and glob segments

4. **Middleware Pipes** (`src/amber/pipes/`): Pipeline-based HTTP request processing — CSRF, Session, Flash, Logger, CORS, Static, Error, ClientIp, ApiVersion, PoweredByAmber

5. **WebSockets** (`src/amber/websockets/`): Channel-based real-time communication with presence tracking, message decoders, connection recovery, and adapter-backed PubSub

6. **Configuration** (`src/amber/configuration/`): Typed configuration structs with YAML loading, environment variable overrides (`AMBER_` prefix), validation, and custom registry

7. **Schema API** (`src/amber/schema/`): Request validation and type coercion. Define schemas with field types, validators (required, length, format, range, pattern, enum), and parsers (JSON, URL-encoded and multipart forms, query, CBOR, COSE); XML bodies are answered with 415

8. **Jobs** (`src/amber/jobs/`): Background job processing with work-stealing pattern — idle web instances pick up queued jobs. Retry logic, queue adapters

9. **Mailer** (`src/amber/mailer/`): Email composition with fluent API, SMTP adapter, memory adapter for testing

10. **Testing** (`src/amber/testing/`): ContextBuilder for request simulation, assertions, WebSocket test helpers

11. **Adapters** (`src/amber/adapters/`): Pluggable backends for sessions (Memory, with adapter interface for Redis/others) and PubSub (Memory, with adapter interface). Factory pattern for runtime selection

12. **Markdown** (`src/amber/markdown/`): GFM-compatible renderer with autolinks, footnotes, table of contents, syntax highlighting

13. **Session Security** (`src/amber/support/`): MessageEncryptor and MessageVerifier with SHA256, SameSite cookies, key rotation, session regeneration

14. **DSL** (`src/amber/dsl/`): Macros for server configuration, router definition, pipeline composition, and callback registration

### Template Engine

ECR (Embedded Crystal) only — part of Crystal stdlib. Kilt/Slang/Liquid have been removed.

### Key Design Patterns

- **Adapter Pattern**: Sessions, PubSub, jobs, and mailer use adapters for different backends
- **Pipeline Pattern**: HTTP requests flow through configurable middleware pipes
- **DSL Approach**: Router and server configuration use Crystal macros for clean syntax
- **Work-Stealing**: Background jobs distributed across idle web instances
- **Convention over Configuration**: Sensible defaults with typed overrides

### Using Amber Without HTTP Server (Native Apps)

Amber can be used as a pattern library for native desktop/mobile apps without starting the HTTP server. This is useful when you want Amber's configuration, controllers-as-event-handlers, and process managers but use a native event loop instead.

**Settings API:**
```crystal
require "amber"

# Correct: access settings directly
Amber.settings.name = "My Native App"
puts Amber.env  # => "development"

# WRONG: Amber::Server.configure creates an HTTP server instance
# Amber::Server.configure { |s| s.name = "..." }  # Don't do this

# WRONG: Amber::Server.settings doesn't exist
# Amber::Server.settings.name  # NoMethodError
```

**Key point:** `Amber.settings` returns `Amber::Environment::Settings` and can be used standalone. `Amber::Server.configure` yields settings but also instantiates `Amber::Server.instance` which initializes HTTP-related adapters.

### External Dependencies

- **Grant ORM**: Separate shard — ActiveRecord-style ORM for V2 (publishing to the amberframework org soon)
- **Micrate**: Separate shard (`amberframework/micrate`) — SQL migrations that Amber CLI runs as `amber database migrate`, `rollback`, and `status`
- **Gemma**: Separate shard — file attachments, storage, and delivery; an ecosystem preview, not part of the web release gate
- **Mica**: Separate shard (`amberframework/mica`, v0.1.0) — pure-Crystal parsing of untrusted input to published standards, under a work budget. Today it parses XML 1.0 and 1.1 with Namespaces (streaming reader, DOM, builder, XPath 1.0), with no C parsing library and no network or file access while parsing. It is the opt-in XML request parser; Amber itself does not depend on it. See "Accepting XML request bodies" below.
- **CLI**: Separate project (`amber_cli`) — not part of this repo
- **Asset Pipeline**: Separate project (`amberframework/asset_pipeline`) — not part of this repo

The website's crew page gives each boundary a character: Amber (framework), Grant (records), and Gemma (files): https://amberframework.org/characters

### Accepting XML request bodies

Amber answers `application/xml`, `text/xml` and other `+xml` bodies with `415 Unsupported Media Type` until the app registers a parser. To accept XML through Mica, do all three steps; with any one missing, XML requests still get 415.

1. Add the shard to `shard.yml` and install it (`shards install`, or `minecart install` with Amber CLI):

   ```yaml
   dependencies:
     mica:
       github: amberframework/mica
       version: 0.1.0
   ```

2. Register one parser per media type at boot, in `config/initializers/request_body_parsers.cr`. Make sure `config/application.cr` loads the initializers (`require "./initializers/*"`); apps generated by Amber CLI 2.0.7 and earlier load `config/*.cr` only.

   ```crystal
   require "mica/xml/fields"

   {"application/xml", "text/xml"}.each do |media_type|
     Amber::Schema::Parser::ParserRegistry.register_body_parser(media_type) do |body|
       Mica::XML::Fields.read(body)
     end
   end
   ```

3. List the media types in each action's schema:

   ```crystal
   class CreateOrderSchema < Amber::Schema::Definition
     content_type "application/json", "application/xml", "text/xml"
     field :sku, String, required: true
   end
   ```

Full guide: https://github.com/amberframework/amber/blob/v2.0.0-beta.6/docs/guides/schema-api.md#opt-in-request-body-parsers

## Key File Paths

| Area | Path |
|------|------|
| Entry point | `src/amber.cr` |
| Configuration | `src/amber/configuration/` |
| Controllers | `src/amber/controller/` |
| Router + Engine | `src/amber/router/`, `src/amber/router/engine/` |
| Named Routes | `src/amber/router/named_routes.cr` |
| Constraints | `src/amber/router/constraints/` |
| Middleware | `src/amber/pipes/` |
| WebSockets | `src/amber/websockets/` |
| Schema API | `src/amber/schema/` |
| Jobs | `src/amber/jobs/` |
| Mailer | `src/amber/mailer/` |
| Testing | `src/amber/testing/` |
| Adapters | `src/amber/adapters/` |
| Markdown | `src/amber/markdown/` |
| Session Security | `src/amber/support/message_encryptor.cr`, `message_verifier.cr` |
| DSL | `src/amber/dsl/` |
