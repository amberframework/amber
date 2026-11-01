# CLAUDE.md

## Project Overview

Amber V2 is a web application framework written in Crystal. It provides an efficient, cohesive framework that embraces Crystal's language philosophies with near-zero runtime dependencies.

**Version**: the 2.0 beta line; `shard.yml` names the exact release
**Crystal**: >= 1.20.0, < 2.0 (as `shard.yml` declares)
**License**: MIT
**Dependencies**: ameba (dev only) — framework is entirely self-contained at runtime

## Development Commands

These commands are for working on the Amber framework repository itself. In an application, install dependencies with `minecart install --frozen` (see "Accepting XML request bodies" for adding a shard).

```bash
# Install dependencies from the committed shard.lock (ameba only)
shards install --frozen

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

7. **Schema API** (`src/amber/schema/`): Request validation and type coercion. Define schemas with field types, validators (required, length, format, range, pattern, enum), and parsers (JSON, URL-encoded and multipart forms, query, CBOR, COSE); XML bodies are answered with 415 by default, until the app registers a parser (see "Accepting XML request bodies")

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

An action bound to a request schema answers an `application/xml`, `text/xml` or other `+xml` body with `415 Unsupported Media Type` until the app registers a parser for that media type. To accept XML through Mica, do all three steps. Without the parser registration, the initializer load, or the XML media type in the bound schema, those requests still get 415; without the shard, the app does not build.

1. Add the shard to `shard.yml`, pinned to the v0.1.0 release commit:

   ```yaml
   dependencies:
     mica:
       github: amberframework/mica
       commit: 6a4866e59c9c1bde099556315febebbbd6b635f3 # v0.1.0
   ```

   Then run `minecart update mica` and check that `shard.lock` records exactly these two lines for Mica before you commit it:

   ```yaml
       version: 0.1.0+git.commit.6a4866e59c9c1bde099556315febebbbd6b635f3
       checksum: git-tree:6e9f3506210f1580c813c475c170362b5412dca7
   ```

   Later installs run `minecart install --frozen`.

2. Register one parser per media type at boot, in `config/initializers/request_body_parsers.cr`. Make sure `config/application.cr` loads the initializers (`require "./initializers/*"`); apps generated by Amber CLI 2.0.7 and earlier load `config/*.cr` only.

   ```crystal
   require "mica/xml/fields"

   {"application/xml", "text/xml"}.each do |media_type|
     Amber::Schema::Parser::ParserRegistry.register_body_parser(media_type) do |body|
       Mica::XML::Fields.read(body)
     end
   end
   ```

3. List the media types in the request schema, and bind the schema to the action:

   ```crystal
   class CreateOrderSchema < Amber::Schema::Definition
     content_type "application/json", "application/xml", "text/xml"
     field :sku, String, required: true
   end

   class OrdersController < ApplicationController
     schema :create, CreateOrderSchema

     def create
       input = validated_as(CreateOrderSchema)
       # ...
     end
   end
   ```


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
