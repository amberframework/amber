# Plan: an Amber V2 app that links no regex engine and no C parsing library

Status: draft, 2026-11-06. Owner: Amber V2 maintainers. First PR: the router
(this branch, `feature/router-typed-constraints`).

## Goal

A compiled Amber V2 application links no regular-expression engine (PCRE2) and
no C parsing library (libyaml, libxml2). Every job that Amber does with stdlib
`Regex` today moves to one of three places:

1. **Typed, linear-time code with no engine at all**, where the job is a fixed
   shape: route parameter rules, extension and port parsing, suffix rules.
2. **A Mica format**, where the job is parsing a published format (YAML,
   cookies, form keys, HTML, Markdown).
3. **The Mica regex engine**, for patterns that stay patterns (user-supplied
   `pattern:` validators, CORS origin patterns, locale data). This is milestone
   **M-7** of the approved Mica/Beryl/Amber V2 plan (report followup-34, section
   3.4, Seth's ruling of 2026-10-25), made crystal-alpha's default `Regex`
   engine at **M-9**, with PCRE2 behind `-Duse_pcre2`. Amber code that keeps
   using `Regex` links no PCRE2 once M-9 ships; until then it does.

The bar is the one `amberframework/mica`'s `scripts/check_linkage.sh` enforces:
`otool -L` (or `ldd`) shows no `libpcre2`, `libyaml` or `libxml2`, and `nm`
shows no `pcre2_` symbol. Section 5 covers OpenSSL and zlib, which this bar
does not yet decide.

## 1. Proof: what a minimal Amber V2 app links today

The app: one controller, two routes (`/` and `/items/:id`), the generated
`:web` pipeline (Error, Logger, Session, Flash, CSRF), `Amber::Server.start`.
Built twice on macOS 26 (Apple Silicon), Crystal 1.21.0 [9c1e8ec64]
(crystal-alpha), `shards-alpha install` from a lock with a `git-tree` checksum:

| Variant | Amber commit | `shard.lock` checksum |
|---|---|---|
| beta.9 | `34a93352eaa89501d24e2b9ff90b058209a22720` (tag `v2.0.0-beta.9`) | `git-tree:f1e7332d02229aec58ab5303ade7fc6c9d14fcee` |
| v2-dev HEAD | `9ce693c43b3734e719d4dc7eb2f5fb3c839a6e5b` (merge of #1440) | `git-tree:f1e7332d02229aec58ab5303ade7fc6c9d14fcee` |

The two trees are identical (same `git-tree` checksum; `git diff` is empty),
so the two binaries link the same libraries. `otool -L bin/probe_app`, both
variants:

```
/opt/homebrew/opt/libyaml/lib/libyaml-0.2.dylib (compatibility version 3.0.0, current version 3.9.0)
/usr/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.2.12)
/opt/homebrew/opt/openssl@4/lib/libssl.4.dylib (compatibility version 4.0.0, current version 4.0.0)
/opt/homebrew/opt/openssl@4/lib/libcrypto.4.dylib (compatibility version 4.0.0, current version 4.0.0)
/opt/homebrew/opt/pcre2/lib/libpcre2-8.0.dylib (compatibility version 17.0.0, current version 17.1.0)
/opt/homebrew/opt/bdw-gc/lib/libgc.1.dylib (compatibility version 1.0.0, current version 1.5.6)
/usr/lib/libiconv.2.dylib (compatibility version 7.0.0, current version 7.0.0)
/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1356.0.0)
```

The binary served `GET /items/42` with `item 42` and `GET /` with 200. These
app builds are debug builds (no `--release`); linkage is decided by which `lib`
bindings the program reaches, not by optimization, and the `--release`
controls below agree.

After PR 1 (the same app on this branch, Amber `1d88adeb`, lock checksum
`git-tree:533c9636e0e73fada71e71f6009a9c4a56c69c09`) `otool -L` prints the
same eight libraries: the router no longer needs PCRE2, but the cookie store,
the responders, `server.cr:65` and `env_override.cr:244` are still on every
app's path (section 2). The router on its own is clean; see the last two rows
of the next table.

Control programs, same compiler, `--release`:

| Program | Links beyond libgc, libiconv, libSystem |
|---|---|
| `puts 1` | nothing |
| `require "http/server"`, one handler | libz, libssl, libcrypto |
| the same with `-Dwithout_openssl -Dwithout_zlib` | nothing |
| `require "http"` + `HTTP::Cookie::Parser.parse_cookies("a=b")` | adds libpcre2-8 |
| `require "http"` + `JSON.parse`, `URI.parse`, `HTTP::LogHandler`, `HTTP::ErrorHandler` | no libpcre2 |
| `Amber::Router::RouteSet` with three Regex constraints (beta.9) | libpcre2-8 (13 undefined `pcre2_` symbols) |
| the same routes with typed rules (this branch) | nothing (0 `pcre2_` symbols) |

So stdlib's HTTP server alone brings OpenSSL and zlib, and stdlib's cookie
parser alone brings PCRE2; Amber adds libyaml and its own Regex sites.

## 2. Every source of a non-runtime library, one line each

Line numbers are at beta.9 (`34a93352`). "Every app" marks code on the path of
the minimal app above.

### libpcre2-8: stdlib, reached by Amber

- `stdlib http/cookie.cr:264-273` (`HTTP::Cookie::Parser::Regex`), reached from `src/amber/router/cookies/store.cr:22,30` (`parse_cookies` on `Cookie` and request `Set-Cookie` headers). Every app with a session or flash.

### libpcre2-8: Amber's router (removed by PR 1, this branch)

- `src/amber/router/engine/segments/variable_segment.cr:6,15`: a variable segment's constraint is a `Regex` matched with `=~`. Every app with a constrained route.
- `src/amber/router/engine/route_set.cr:55,516,531,536,550`: constraints stored as `Hash(String, Regex)`.
- `src/amber/router/route.cr:15`: `Route#constraints` defaults to `{} of String => Regex`.
- `src/amber/router/constraint_presets.cr:5-10`: six preset patterns (`:numeric`, `:uuid`, `:slug`, `:alpha`, `:alnum`, `:hex`).
- `src/amber/router/router.cr:9,238,282`: `PATH_EXT_REGEX` finds a response extension (`.json`, `.md`) on every path that contains a dot. Every app.
- `src/amber/router/request.cr:183`: `HTTP::Request#port` reads the `Host` header with `/.*:(\d+)/`.
- `src/amber/router/params.cr:13`: unused alias `TYPE_EXT_REGEX`.
- `src/amber/dsl/router.cr:27,94,105,119` and `src/amber/dsl/schema_router.cr:22,95,106,120`: the route macros' `constraints` default is `{} of String => Regex`.

### libpcre2-8: the rest of Amber (fixed patterns)

- `src/amber/controller/helpers/responders.cr:19,20,173`: `TYPE_EXT_REGEX`, `ACCEPT_SEPARATOR_REGEX`; the responder reads the path extension with a regex. Every app with `respond_with`.
- `src/amber/support/mime_types.cr:6,7,652`: the same two patterns over the full MIME table.
- `src/amber/server/server.cr:65`: `project_name` is `name.gsub(/\W/, "_")`. Every app.
- `src/amber/configuration/env_override.cr:244`: `env_name` is `gsub(/[^A-Z0-9]/, "_")`. Every app.
- `src/amber/pipes/static.cr:26`: `FINGERPRINT_PATTERN` for asset fingerprints.
- `src/amber/pipes/cors.cr:29`: the default origin list contains `%r()`.
- `src/amber/assets.cr:110,120,198,225`: digest, SRI, URL scheme and slash checks for assets.
- `src/amber/support/message_verifier.cr:27`: compares an error message with `%r{invalid base64}`. Every app with sessions.
- `src/amber/support/inflector.cr:50-59`: ten singular suffix rules.
- `src/amber/controller/helpers/route.cr:16`: `controller_name` strips `Controller$`.
- `src/amber/controller/helpers/text_helpers.cr:43,57,69,89`: `highlight`, `simple_format`, `word_wrap`, `strip_tags`.
- `src/amber/controller/helpers/number_helpers.cr:18,46`: digit grouping with a lookahead.
- `src/amber/schema/type_coercion.cr:63,66`, `src/amber/schema/validators/type.cr:31,33`, `src/amber/schema/open_api.cr:281,319`: parse type names (`Array(...)`, `Hash(String, ...)`) and path parameters.
- `src/amber/schema/parsers/json_parser.cr:194,313,327,370,375`, `src/amber/schema/parsers/query_parser.cr:78,124`: bracketed form keys and number shapes.
- `src/amber/schema/parsers/sanitizer.cr:67,69,77`: non-printable removal, whitespace, tag removal.
- `src/amber/schema/definition.cr:887,926,930,934`, `src/amber/schema/validators/format.cr:21-27,75`: email, IPv4, IPv6, hostname, URL, UUID, phone and time formats.
- `src/amber/extensions/string.cr:10-104`: 14 `String#email?`-style predicates added to stdlib `String`.
- `src/amber/support/locale_formats.cr` (66 patterns, two with lookaheads at 44 and 74): per-locale phone and postal formats.
- `src/amber/support/backtracer/configuration.cr:4,7,17,26,43,53,66,72`: backtrace line parsing for the error page.
- `src/amber/markdown/**` (51 patterns: `rule.cr` 30, `parsers/inline.cr` 5, `html_entities.cr` 4, `rules/heading.cr` 4, `rules/code_block.cr` 3, `utils.cr` 2, `parsers/block.cr`, `rules/html_block.cr`, `rules/table.cr`, `rules/thematic_break.cr` 1 each; two lookaheads in `code_block.cr:5,6`).

### libpcre2-8: Amber APIs that take a pattern from the application

- `src/amber/schema/definition.cr:866,940`: `Regex.new` on a schema's `pattern` and custom `format` strings.
- `src/amber/schema/validators/pattern.cr:4`, `src/amber/schema/validators/format.cr:30`: validators that take a `Regex`.
- `src/amber/schema/parsers/multipart_parser.cr:79`: `Regex.new(pattern)`.
- `src/amber/pipes/cors.cr:20,130`: `OriginType = Array(String | Regex)`.

### Compile time only (no linkage)

- `src/amber/controller/helpers/render.cr:18,19,21,23`: `gsub` inside `{{ }}` macros; the compiler's host engine runs them, nothing reaches the binary. Covered by M-9's host-engine gate.

### libyaml

- `src/amber/environment.cr:14`: `Settings.from_yaml`. Every app.
- `src/amber/configuration/{server,security_headers,pubsub,session,mailer,database,logging,jobs}_config.cr`: `include YAML::Serializable`. Every app.
- `src/amber/configuration/env_override.cr:108,142`: `YAML.build`, `YAML::Nodes.parse` for `AMBER_*` overrides. Every app.

### libssl and libcrypto

- `stdlib http/server.cr:10`: `require "openssl"` unless `-Dwithout_openssl`. Every app.
- `src/amber/server/ssl.cr:1,9`: TLS listener.
- `src/amber/support/message_verifier.cr:1,42,59,77`, `src/amber/support/message_encryptor.cr:2,3,69,89,100,115,122`, `src/amber/router/flash.cr:3`: HMAC and AES for signed and encrypted cookies. Every app with sessions.
- `src/amber/schema/cose.cr:2,5`: COSE signatures (`lib LibCrypto`).
- `src/amber/mailer/smtp_adapter.cr:2,82`: SMTP STARTTLS.

### libz

- `stdlib http/common.cr:3,4`: `require "compress/deflate"`, `"compress/gzip"` unless `-Dwithout_zlib`. Every app. Amber itself uses no `Compress`.

## 3. Replacements, site by site

### 3a. The router (PR 1): typed rules, no engine

A route parameter rule is any type that includes `Amber::Router::ParamConstraint`
(`matches?(segment : String) : Bool`, `to_s(io)`, and an overridable
`matches_span?(path, byte_offset, bytesize)` that the router calls while it walks
the path, so the built-in rules read the bytes in place). Built-in rules live in
`Amber::Router::ParamConstraints`: `CharacterRun` (an ASCII bitmap with length
bounds; `NUMERIC`, `ALPHA`, `ALNUM`, `HEX`, `with_length`), `Slug`, `Uuid`,
`OneOf`, and `Custom` (a labeled block). Each built-in reads each byte once.
A rule judges the whole segment.

Before (beta.9):

```crystal
routes :web do
  get "/users/:id", UsersController, :show, {"id" => /\d+/}
  get "/posts/:slug", PostsController, :show, {"slug" => /[a-z0-9\-]+/}
  get "/codes/:code", CodesController, :show, {"code" => /\d\d\d/}
  get "/files/:name", FilesController, :show, {"name" => /\.json\z/}
  resources "orders", OrdersController, constraints: {"id" => /\d+/}
end
```

After:

```crystal
routes :web do
  get "/users/:id", UsersController, :show, {"id" => :numeric}
  get "/posts/:slug", PostsController, :show, {slug: :slug}
  get "/codes/:code", CodesController, :show,
    {"code" => Amber::Router::ParamConstraints::NUMERIC.with_length(3)}
  get "/files/:name", FilesController, :show,
    {"name" => Amber::Router::ParamConstraints::Custom.new("json_file", &.ends_with?(".json"))}
  resources "orders", OrdersController, constraints: {"id" => :numeric}
end

# A reusable rule is a type:
struct EvenPageNumber
  include Amber::Router::ParamConstraint

  def matches?(segment : String) : Bool
    if page_number = segment.to_i?
      page_number.even?
    else
      false
    end
  end

  def to_s(io : IO) : Nil
    io << "even_page_number"
  end
end
```

Breaking, by design for the beta line: a `Regex` constraint no longer
compiles (`expected argument #1 to 'Amber::Router::ParamConstraints.resolve'
to be Amber::Router::ParamConstraint or Symbol, not Regex`). An unanchored
pattern that matched part of a segment (`/\d\d\d/` matched `he110`) becomes a
rule for the whole segment. An unknown preset symbol raises
`ParamConstraints::UnknownPresetError` when the routes are drawn.

The router's other two Regex jobs become String code: `PATH_EXTENSIONS`
(`[".html", ".json", ...]` from `Content::TYPE`) with `ends_with?`, and
`HTTP::Request#port` with `rpartition(':')` plus an all-digits check (a bare
`[::1]` no longer reports port 1).

### 3b. Every other site

| Site (section 2) | Replacement | PR |
|---|---|---|
| `responders.cr:19,20,173`, `mime_types.cr:6,7,652` | extension: the router's `ends_with?` lookup over the type keys (`MIME_TYPES` keyed by extension, one `rpartition('.')` and a hash lookup); Accept separator: `split(',')` + `strip` | PR 2 |
| `server.cr:65`, `env_override.cr:244`, `route.cr:16`, `message_verifier.cr:27`, `cors.cr:29` default, `static.cr:26`, `assets.cr:110,120,198,225` | plain String: `each_char` maps, `rchop("Controller")`, `message.includes?`, a default of `["*"]`, byte scans for hex digests, SRI and fingerprints, `starts_with?` with `compare(case_insensitive: true)`, `squeeze('/')` | PR 2 |
| `inflector.cr:50-59` | a suffix table of `{suffix, replacement}` String pairs with case-insensitive `ends_with?` | PR 2 |
| `type_coercion.cr:63,66`, `validators/type.cr:31,33`, `open_api.cr:281,319` | String `starts_with?`/`ends_with?` on type names; path parameters by splitting on `/` | PR 2 |
| `text_helpers.cr:43,57,69,89` | `highlight`: case-insensitive scan with `index`; `simple_format`: split on blank-line runs by a line scan; `word_wrap`: a word-by-word line builder; `strip_tags`: Mica::HTML (A7), and until then a byte scan | PR 2 (A7 for `strip_tags`) |
| `number_helpers.cr:18,46` (lookahead) | digit grouping by index arithmetic | PR 3 |
| `markdown/rules/code_block.cr:5,6` (lookaheads) | fence detection by a byte scan | PR 3 |
| `locale_formats.cr:44,74` (lookaheads) | the same patterns rewritten without lookaround (alternation over the excluded prefixes) | PR 3 |
| `extensions/string.cr:10-104`, `definition.cr:887,926,930,934`, `validators/format.cr:21-27,75` | one `Amber::Support::TextFormats` module of hand-written linear checks (email, URL, IPv4, IPv6, hostname, UUID, MAC, hex color, phone E.164, time) shared by both; the `String` reopenings become deprecated wrappers, then are removed | PR 4 |
| `json_parser.cr:194,313,327,370,375`, `query_parser.cr:78,124`, `multipart_parser.cr:79` | Mica `Form::Pairs` and `NestedKeys` (Mica M1, Amber step A1); number shapes by `to_i?`/`to_f?` with a strict-grammar byte check | PR 5 (A1) |
| `cookies/store.cr:22,30` (stdlib `HTTP::Cookie::Parser`) | `Mica::HTTP::CookieHeader` (report 17 M3.5, step A6b); the request-side `Set-Cookie` path is removed | PR 6 (A6b) |
| libyaml: `environment.cr:14`, `configuration/*_config.cr`, `env_override.cr:108,142` | `Mica::YAML` (Mica M4, step A5) | PR 7 (A5) |
| `markdown/**`, `sanitizer.cr:77`, `strip_tags` | `Mica::Markdown`, `Mica::HTML` (Mica M8, step A7); until then the markdown patterns stay `Regex` and run on the M-7 engine | PR 8 (A7) |
| `sanitizer.cr:67,69` | byte scan for printable ASCII; `split` + `join(' ')` for whitespace | PR 2 |
| `backtracer/configuration.cr` (8 patterns, named groups) | stays `Regex` (dev error page; every construct is in M-7's dialect) | M-7/M-9, no Amber PR |
| `locale_formats.cr` (the other 64 patterns) | stay `Regex` literals (locale data; in M-7's dialect after PR 3) | M-7/M-9, no Amber PR |
| application patterns: `definition.cr:866,940`, `validators/pattern.cr`, `validators/format.cr:30`, `multipart_parser.cr:79`, `cors.cr:20,130` | stay `Regex` in the public API; the engine under `Regex` becomes Mica at M-9 | M-7/M-9, no Amber PR |
| `render.cr:18-23` (macro time) | none needed; the host engine is M-9's | M-9 |

## 4. Order of PRs

Each PR is against `v2-dev`, keeps the suite green, and lists in its
description which lines of section 2 it removes.

1. **PR 1, router (this branch).** Typed parameter rules; `PATH_EXTENSIONS`;
   `Request#port` without a regex. `git grep -n Regex -- src/amber/router`
   prints nothing; a `RouteSet` program links no PCRE2.
2. **PR 2, fixed patterns to String code** (no dependency): the PR 2 rows of 3b.
3. **PR 3, the six lookaround sites** (no dependency; also unblocks Amber's
   entries in M-7's 1,714-site corpus).
4. **PR 4, `Amber::Support::TextFormats`** (no dependency).
5. **PR 5, A1** after Mica M1 (`Form::Pairs`, `NestedKeys`).
6. **PR 6, A6b** after Mica M3.5 (`HTTP::CookieHeader`). Removes the last
   PCRE2 use on every app's path from Amber's side.
7. **PR 7, A5** after Mica M4 (`Mica::YAML`). Removes libyaml.
8. **PR 8, A7** after Mica M8 (`Mica::HTML`, `Mica::Markdown`).
9. **PR 9, the link gate**, after M-9 ships in crystal-alpha (or as soon as PRs
   1-8 leave no default-path `Regex`): `scripts/check_linkage.sh` builds the
   probe app of section 1 and a generated app, and fails on `libpcre2`,
   `libyaml`, `libxml2` in `otool -L`/`ldd` or any `pcre2_`/`yaml_` symbol in
   `nm`, with a negative control that links PCRE2 and must fail; CI runs it.

PRs 2-4 can merge in any order after PR 1. After PR 6 and PR 7 a default app
with no Markdown, no `pattern:` validators and no CORS regex origins links no
PCRE2 and no libyaml even before M-9; after M-9 every app does.

## 5. Open question for Seth: OpenSSL and zlib

Stdlib's `HTTP::Server` links libssl, libcrypto and libz in every Crystal web
program unless it is built with `-Dwithout_openssl -Dwithout_zlib`, and Amber
signs and encrypts cookies with OpenSSL's HMAC and AES. Removing them would mean
a pure-Crystal TLS and crypto stack, which is Beryl's territory and a much
larger risk than parsing. **Recommended default:** the zero-linkage bar for
Amber V2 is "no regex engine and no C parsing library" (no libpcre2, libyaml,
libxml2); libssl, libcrypto and libz stay as the accepted crypto and
compression floor, as the beta.6 zero-link evidence already records.

## Lessons applied

- #20261025160648 (Mica regex is crystal-alpha's default, PCRE2 behind a flag): the pattern sites that stay `Regex` are mapped to M-7/M-9 instead of being rewritten, and a construct outside Mica's subset is removed in PR 3 so those sites compile under the default engine.
- #20261030164905 (link footprint of the supply-chain audit): section 1 re-measures it on beta.9; libxml2 is already gone (beta.6), the rest matches.
- #20261027140221 (nothing above low priority left undone): every site in section 2 has a row and a PR in section 3; none is left as a known limitation.
- #20261025215529 (Mica form parsing rejects invalid UTF-8 by default, browser behavior by opt-in): PR 5 (A1) keeps Amber's current reject-or-replace behavior explicit by choosing the option by name.
