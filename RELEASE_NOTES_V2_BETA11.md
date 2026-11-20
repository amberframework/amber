# Amber 2.0.0-beta.11

Amber 2.0.0-beta.11 carries the regex-free path from a JSON API to the whole
default app. An app made with `amber new -d sqlite`, with a Grant model and
asset_pipeline, links no PCRE2.

## What changed

- **No PCRE2 in a default app.** Grant 0.24.0 and asset_pipeline 0.38.0 keep
  `Regex` off their default require paths. The app Amber CLI 2.0.11 generates
  shows no `libpcre2` in `otool -L` or `ldd` and no `pcre2_` symbol in `nm`,
  before and after `amber generate scaffold` adds a Grant model. Amber CLI CI
  runs this check on macOS and Linux, and its control program that uses `Regex`
  must show PCRE2.
- **`respond_with` takes a `NamedTuple` (#1425, #1451).** The documented call now
  compiles. The tuple becomes `Hash(String, JSON::Any)` through its JSON form, so
  `Int32`, arrays and nested tuples work as values. `scripts/check_linkage.sh`
  answers one route this way.
- **`respond_with` takes any JSON-serializable `Hash` (#1451).**
  `Hash(String, String)`, `Hash(Symbol, Int32)` and the like used to fail to
  compile.
- **`Accept` q values count (#1451).** `respond_with` picks among the formats the
  response schema declares and honors `q`. `application/cbor;q=0` no longer
  answers CBOR, and a JSON-only schema answers JSON when JSON is acceptable.
- **A starting heap for the garbage collector (#1452).**
  `server.gc_initial_heap_mib` grows the collector's heap to that many MiB in
  every server process before it takes requests, and
  `AMBER_SERVER_GC_INITIAL_HEAP_MIB` overrides it. The default, 0, keeps the
  collector's own starting size, so existing apps see no change. Amber CLI 2.0.11
  writes 16 into every generated environment file.

## Keeping your app free of PCRE2

An app links PCRE2 again when it uses any of these, and it keeps working:

- `pattern:`, `filename_pattern:` or a custom `format:` on a schema field, and
  `validates_pattern` or a custom `validates_format`
- a `Regex` passed to `Pipe::CORS`, `Validator::Pattern` or `Validator::Format`
- Markdown, `strip_tags`, and the other `String` checks such as `email?` and `phone?`
- `request.cookies`; read `cookies` instead
- `require "grant/regex"` (for `validates_format_of`, the SQLite `REGEXP`
  operator and Regex entries in `filter_attributes`), and Grant's schema
  tooling, schema tenancy and sharding
- `Regex` in your own code

## Breaking changes

None in Amber. Grant 0.24.0 moves `validates_format_of` behind
`require "grant/regex"`; its release notes list the rest.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.11 for new apps. For an existing app, pin the release commit
in `shard.yml`, along with Grant `v0.24.0` and asset_pipeline `v0.38.0`, run
`minecart update amber grant asset_pipeline`, and run `amber setup:agent`. To
start the collector's heap at the size new apps use, set
`gc_initial_heap_mib: 16` under `server:` in each `config/environments/*.yml`.
