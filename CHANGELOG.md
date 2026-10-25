# Changelog

## Unreleased

### Security

- Bound request parameter parsing. A bracket index such as `items[N]` is now
  converted with a checked conversion and must be at most
  `params.max_array_index` (default 100) and at most
  `params.max_array_index_gap` (default 32) past the end of its array; the
  empty entries added to fill gaps are capped per request by
  `params.max_array_padding` (default 1,000). Previously a single request
  could make Amber pad an array to the index it named, or raise an overflow
  error that surfaced as a 500.
- Add explicit defaults for the number of parameters (`max_params`, 1,000),
  key nesting depth (`max_nesting_depth`, 32), key length (`max_key_bytes`,
  1 KiB), field value length (`max_value_bytes`, 1 MiB), URL-encoded body
  size (`max_form_body_bytes`, 8 MiB), multipart body size
  (`max_multipart_body_bytes`, 128 MiB), multipart part headers
  (`max_part_header_bytes`, 16 KiB), and uploaded file size
  (`max_file_bytes`, 64 MiB). Query strings and URL-encoded bodies are
  scanned byte by byte (`&` and `;` both separate pairs), with key, value and
  body sizes enforced as the bytes arrive; the query is read from the raw
  request target before the URI is parsed. Multipart bodies, headers and
  files are counted while they stream, and bounded reads keep no more than
  their limit. JSON, XML and other document bodies read for schemas or
  `params` are bounded by `max_document_body_bytes` (8 MiB).
- Each request has one parameter budget (`HTTP::Request#param_budget`)
  shared by its query string, body, and schema conversion, so counts and
  array padding are cumulative. `HTTP::Request#query_params` checks the query
  against it before parsing, which covers every reader of the query string.
  `HTTP::Request#form_params` and `#form_params?` reuse Amber's bounded,
  cached form parse for any request method, so a middleware or action read
  of a URL-encoded body is bounded too and shares one result with `params`.
- URL-encoded and multipart bodies are recognized by their media type,
  compared without regard to letter case, rather than by a prefix of the
  `Content-Type` header.
- Every query, form and multipart pair is checked when it is admitted, so
  plain `params` readers see the same limits as schema contracts: a key
  nested deeper than `max_nesting_depth`, or a bracketed number above
  `max_array_index` (or negative), is answered with `400 Bad Request`.
  **Compatibility:** a form that names records by id in brackets, such as
  `users[1700][name]`, now needs `params.max_array_index` raised to cover
  those ids.
- A request beyond any limit is answered with `400 Bad Request` (schema
  contracts report the `parameter_limit_exceeded` code). Configure the limits
  in the new `params:` section of `config/environments/<env>.yml` or with
  `AMBER_PARAMS_<KEY>` environment variables; the loader validates them at
  boot, and V1-format settings files accept the same section and overrides.
- Uploaded files are copied into a tempfile with a fixed `amber-upload`
  name keeping a plain extension, and `Amber::Router::File#size` reports the
  bytes received rather than the client's declared size. During the action
  `params.files["doc"].file` is a readable handle, opened on first use;
  `#path` names the tempfile. Amber closes that handle and deletes upload
  tempfiles when the request finishes, when a later part is rejected, or
  when a later part with the same name replaces one. **To keep an upload,
  call `Amber::Router::File#move_to(path)` during the action, or `#retain!`
  to keep the tempfile at `#path` and take over deleting it, for example
  before passing the path to a background job.** Malformed multipart framing
  or part metadata is answered with `400 Bad Request`
  (`Amber::Exceptions::BadRequest`).
- WebSocket routes read each connection through
  `Amber::WebSockets::BoundedProtocol`, which caps a message across its
  frames and fragments as they arrive (`max_websocket_message_bytes`,
  2 MiB) and closes the connection with code 1009 when it is exceeded. The
  handshake's query string is checked before the 101 response.
  `BinaryDecoder` defaults its frame limit to the ingress limit, and a
  smaller decoder limit also closes the socket with 1009.
- Upload tempfiles live in one directory per user,
  `<tmpdir>/amber-uploads-<uid>`, created with mode 0700 and checked to be
  owned by that user, which every worker and restart reuses. Cleanup removes
  a tempfile only when Amber still owns it and its path, when checked, still
  names the file Amber created. If another local user has claimed that
  directory in a shared temporary directory, the process uses a new
  private directory with an unpredictable name instead. A move across file
  systems copies to a file beside the destination and renames it into
  place, so a failed copy leaves both files as they were.
- XML extraction measures each node's text once, before copying it, and
  checks every extracted key and value against the request's limits (key
  length and depth, value length, and at most four times
  `max_document_body_bytes` in all, XPath fields included), so nested
  elements cannot multiply the text copied out of a document. Text and
  attribute values are measured in libxml's buffers before they are copied.
  An XML document may hold at most `params.max_document_nodes` nodes
  (default 100,000): a well-formed document is counted while it streams,
  before its tree is built, and a recovered malformed one is counted
  before any field is extracted. **XML request bodies may not contain a
  document type declaration (`<!DOCTYPE ...>`)**; one that does is answered
  with `400 Bad Request`, so request XML never defines or expands entities.
- A rejected request body is remembered on the request
  (`HTTP::Request#guard_body_read`): every later read of `params`,
  `form_params`, or a schema contract for that request raises the same
  error, so a caller that catches it never sees a parse of the bytes left
  in the stream. Rejections raised after the body was read (such as the
  node limit, or a CBOR or COSE decoding error) are remembered the same
  way. Upload cleanup continues past a file that fails to close or delete,
  and a failed delete is retried at the end of the request.
- `Amber::Schema::RequestParseError` raised from an action (for example by
  calling `ParserRegistry.parse_request` directly) is answered with its own
  status, such as 400, by the pipeline and the Error pipe, rather than 500.
- The pipeline detects a WebSocket upgrade the way the WebSocket handler
  does (`Upgrade: websocket` in any letter case, with `Upgrade` in
  `Connection`), and a route that only has a socket handler no longer
  raises `NilAssertionError`: an upgrade reaches the handler, and a plain
  request is answered with 404.
- The WebSocket binary decoder caps each frame (`max_frame_bytes:`, by
  default `max_websocket_message_bytes`) before Base64 decoding, rejects a length prefix or field count
  larger than the message, and rejects bytes after the declared fields.
- Indexed nested keys such as `items[0][name]=alice` now build
  `[{"name" => "alice"}]` in `JSONParser` instead of a null entry.

## 2.0.0-beta.5 (2026-08-13)

This release makes Amber V2 schemas executable request and response contracts,
keeps the deprecated V1 validator working for incremental upgrades, and moves
the optimized router and request path into the V2 release line.

- Enforce declared controller request schemas before actions and expose
  request-local typed values through `validated_as`.
- Validate response status, content type, and shape before sending a declared
  API response.
- Generate OpenAPI 3.1 operations from the same enforced request and response
  contracts.
- Parse JSON, XML, URL-encoded forms, multipart forms, bounded CBOR, and
  authenticated COSE Encrypt0 requests.
- Negotiate JSON, CBOR, and COSE responses with explicit contract errors for
  malformed, unsupported, invalid, or unavailable request paths.
- Let server-rendered controllers override schema-failure rendering so ECR
  forms can return field errors with the correct HTTP status.
- Make the allocation-light span router the V2 default and reduce request,
  params, pipeline, and responder allocations.
- Preserve `params.validation` as a functional deprecated compatibility bridge;
  applications may upgrade first and migrate one action at a time.

## 2.0.0-beta.4 (2026-08-11)

This release adds the framework side of Amber V2's production static-asset
contract while preserving the database-backed web path from beta.3.

- Resolve logical asset names through a strict, reloadable manifest and expose
  ECR helpers for stylesheets, modules, import maps, images, and favicons.
- Emit Subresource Integrity metadata for stylesheets, JavaScript modules, and
  module preloads.
- Serve fingerprinted files with immutable caching, correct portable MIME
  types, configured static headers, conditional requests, byte ranges, and
  precompressed gzip variants.
- Prefer `AMBER_DATABASE_URL` while accepting the conventional `DATABASE_URL`
  fallback used by many hosting providers.
- Reject malformed or inconsistent asset manifests at startup instead of
  silently emitting broken public URLs.

## 2.0.0-beta.3 (2026-08-11)

This release completes the framework side of the database-backed default web
application introduced by Amber CLI 2.0.4.

- Parse URL-encoded and multipart form bodies in schema controllers, including
  requests whose bodies were already read by routing or CSRF protection.
- Repair background-job work stealing so idle workers can claim queued work
  without corrupting the request activity count.
- Normalize rendered view paths on Windows.
- Document `respond_with` HTML and JSON negotiation with executable examples.

## 2.0.0-beta.2 (2026-07-31)

This release supersedes beta.1 for the supported Amber CLI web-app path.

- Replaced `Process.fork` in the HTTP server cluster launcher with portable
  process spawning. This restores application compilation and launch with
  Crystal 1.21's default multithreaded runtime on macOS and Linux.
- Kept the beta.1 framework API and release-gated surface unchanged.

## 2.0.0-beta.1 (2026-07-31)

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

`Amber::Server.configure` supports both the V1 block-parameter form and the V2
DSL form. New applications use the DSL form, while existing applications can
migrate incrementally without changing every configuration assignment at once.

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
