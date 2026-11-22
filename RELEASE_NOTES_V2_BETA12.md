# Amber 2.0.0-beta.12

Amber 2.0.0-beta.12 makes a default app smaller in memory and safer at the
door: it refuses compressed request bodies, stops keeping a session for every
visitor, and allocates less on every request.

## What changed

- **Compressed request bodies are refused (#1454).** A request with a
  compressed body is answered `415 Unsupported Media Type` before routing or
  any pipe reads it. Crystal before 1.21.1 inflates gzip and deflate request
  bodies with no size limit
  ([GHSA-jfq5-c3x6-w7jj](https://github.com/crystal-lang/crystal/security/advisories/GHSA-jfq5-c3x6-w7jj)),
  so a 1 MiB body could become 1 GiB. The guard works on every compiler,
  crystal-alpha 1.21.0 included. An app that accepts compressed uploads sets
  `params.accepts_encoded_request_bodies: true` and bounds the body itself.
- **Sessions follow `session.store` (#1455).** See the behavior change below.
  `Amber::Pipe::Flash` writes the session only when there is a flash to keep
  or clear, so a visitor who never sees a flash gets no session. The memory
  session adapter keeps at most `session.max_memory_sessions` sessions
  (10,000 by default) and drops the one used longest ago. A `:web` route
  served to cookieless clients used to grow to 858 MiB in 90 s; it now stays
  under 15 MiB.
- **The logger allocates nothing when its lines are filtered (#1456).** At the
  default `info` level `Amber::Pipe::Logger` used to build every debug line,
  parse the params and create a session, about 11.8 KB per request, before
  `Log` dropped it.
- **`Amber::Pipe::Compression` (#1457).** It gzips or deflates responses with
  the same bytes as `HTTP::CompressHandler`, but its zlib streams come from
  `malloc` and are reused through a small pool, where `HTTP::CompressHandler`
  allocates about 270 KB from the collected heap for every compressed
  response. Amber CLI 2.0.12 apps use it through `CompressedResponsePipe`.
- **Asset tags are rendered once per manifest (#1458).** `stylesheet_link_tag`,
  `javascript_include_tag`, `image_tag`, `favicon_tag` and
  `javascript_importmap_tag` return stored HTML on later calls. A generated
  layout's three tags used to cost 6.9 KB per page.

## Behavior change: `signed_cookie` sessions live in the cookie

`store: signed_cookie` is the default in every generated app. Through beta.11
every store, `signed_cookie` included, kept sessions in the server's memory.
From beta.12 a `signed_cookie` or `encrypted_cookie` app keeps the session in
the visitor's cookie and nothing on the server. Session values travel with
every request and must fit in a 4,096-byte cookie (a larger session raises
`Amber::Exceptions::CookieOverflow`), the visitor can read (but not change) a
`signed_cookie` session, and `regenerate_session!` does nothing. An app that
needs server-side sessions sets `store: adapter` under `session:`, or
`AMBER_SESSION_STORE=adapter`.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.12 for new apps. For an existing app, pin the release commit
in `shard.yml`, keep Grant `v0.24.0` and asset_pipeline `v0.38.0`, run
`minecart update amber`, and run `amber setup:agent`. Check the `session:`
section of each `config/environments/*.yml` against the behavior change above.
To use the pooled compressor, make the generated `CompressedResponsePipe` a
subclass of `Amber::Pipe::Compression` with an empty body, or plug
`Amber::Pipe::Compression.new` in its place. New apps start the collector's
heap at 8 MiB (`gc_initial_heap_mib: 8` under `server:`).
