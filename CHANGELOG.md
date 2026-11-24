# Changelog

## Unreleased

**`require "amber/tls"` runs on Beryl: TLS 1.3, no OpenSSL.** The HTTPS
listener and the SMTP mailer's TLS now use Beryl, Amber's own TLS 1.3 written
in Crystal, from the vendored copy (`Amber::Beryl::TLS`). An `amber new --tls`
app links no libssl or libcrypto. TLS 1.3 is the requirement everywhere:
a client or mail server that cannot speak it is refused.

- **HTTPS listener:** the PEM certificate chain (`server.ssl.cert_file`) and
  private key (`server.ssl.key_file`, P-256, RSA or Ed25519), SNI read, ALPN
  `http/1.1`. Each handshake runs in its connection's fiber, and a client
  whose handshake fails ends that connection quietly.
- **Mailer:** STARTTLS (`use_tls`) and, new, implicit TLS
  (`use_implicit_tls`, port 465). The server's chain is verified to the
  Mozilla roots, or to `ca_certificates_file` (new), and must name the
  host. A mail server that offers only TLS 1.2 fails delivery with an error
  that names the TLS 1.3 requirement (`Amber::TLS::TLS_1_3_REQUIREMENT`).
- **Opt-out for one release:** building with `-Duse_openssl` serves the same
  settings from OpenSSL, held to TLS 1.3.
- The vendored Beryl moves to the release with TLS 1.3.

## 2.0.0-beta.15 (2026-11-24)

Amber 2.0.0-beta.15 makes TLS opt-in. On crystal-alpha 1.22.3-incremental-1,
an `amber new -d sqlite` app with a scaffold links no libssl, libcrypto,
libz, libiconv or PCRE2 without any build flag, and peaked at 18.2 MiB of
RSS under load at the 8 MiB heap on an M4 Mac mini, against 20.0 MiB for the
beta.14 app on the same compiler. An app that serves HTTPS itself or sends
mail with `use_tls` adds `require "amber/tls"`. Responses are compressed
with Brotli when the client asks for it, and the vendored Mica and Beryl
move to their current releases. Apps pin asset_pipeline 0.40.0.

**TLS is opt-in: `require "amber/tls"`.** Amber no longer compiles its TLS
listener into every app. An app that serves HTTPS itself (`server.ssl`) or
sends mail over SMTP STARTTLS (mailer `use_tls`) adds `require "amber/tls"`
to `config/application.cr`, right after `require "amber"`; `amber new --tls`
writes it. Without it, a server whose settings ask for TLS stops at start,
before it forks or binds, with `Amber::Exceptions::TLSNotCompiledIn`, whose
message names `require "amber/tls"`. Amber's own files require
`http/server` instead of `http`, so Amber brings in no `HTTP::Client`.
On crystal-alpha with the opt-in TLS standard library (crimson-knight/crystal
`http/server/tls`), a default `amber new -d sqlite` app with a scaffold then
links no libssl or libcrypto without any build flag. On stock Crystal,
`http/server` still requires `openssl`; `-Dwithout_openssl` keeps its
meaning there, and it cannot be combined with `require "amber/tls"`.

**Upgrading:** an existing app that serves HTTPS itself or sends mail with
`use_tls` adds `require "amber/tls"` after `require "amber"` in
`config/application.cr`.

**`Amber::Pipe::Compression` sends Brotli (`br`).** The pipe now offers
Brotli, gzip and deflate and picks the one the client accepts best, with
`Accept-Encoding` q-values honored (RFC 9110, section 12.5.3): `gzip;q=0`
never gets gzip, and on a tie Brotli comes first. Brotli comes from a pinned
copy of Mica's pure-Crystal encoder at quality 5, so an app links no
libbrotli (`Compression.new(brotli_quality: nil)` offers gzip and deflate
only). A body shorter than 1,024 bytes is sent without a content coding.
`Amber::Pipe::Static` serves a precompressed `file.br` as well as `file.gz`,
whichever the request accepts best. The negotiation lives in
`Amber::Pipe::ContentCoding`, which both pipes share.

In an app made by `amber new` on an M4 Mac mini, the rendered
`GET /posts/new` form (1,806 bytes) came back as 808 bytes of Brotli against
961 of gzip, at a median 158 µs per request against 142 µs for gzip and
135 µs uncompressed.

- The vendored copy of Mica under `src/amber/vendor` (`Amber::Mica`) moves from
  `4cc69ece` to amberframework/mica `84812fd1`, pinned by commit and per-file
  sha256 in `MICA_VENDORED.json`. The Brotli writer now sizes its hash tables
  to a body shorter than one metablock (amberframework/mica#34), Brotli
  decoding is at least as fast as libbrotlidec 1.2.1
  (amberframework/mica#35), and the Deflate and Zlib readers stop at the end
  of the stream (amberframework/mica#38). The encoder stays the Z6b port of
  libbrotlienc 1.2.1 (amberframework/mica#36 and amberframework/mica#37),
  which `4cc69ece` already carried. Mica `84812fd1` also holds the HTTP/2 frame codec
  and HPACK (amberframework/mica#30); they are not part of the `compression`
  component Amber vendors.
- The vendored copy of Beryl under `src/amber/vendor` (`Amber::Beryl`) moves from
  `7d678c08` to amberframework/beryl `b1df8cc1`, pinned by commit and per-file
  sha256 in `BERYL_VENDORED.json`. The hashes, HMAC, HKDF and AEADs Amber
  calls now run with the processor's Data Independent Timing mode on
  (amberframework/beryl#9) and give the same bytes. The copy also carries
  Beryl's public-key code (X25519, Ed25519, P-256, P-384 and RSA at
  OpenSSL's speed or better, F3b, amberframework/beryl#14 and
  amberframework/beryl#15), X.509 path validation (amberframework/beryl#10)
  and the x86-64 timing fix that gives every window of a curve
  multiplication fresh operands (amberframework/beryl#18). Amber does not
  call the public-key code.

## 2.0.0-beta.14 (2026-11-22)

Amber 2.0.0-beta.14 lets an app drop libz and OpenSSL. Built with
`-Dwithout_zlib -Dwithout_openssl`, an `amber new -d sqlite` app with a
scaffold links none of PCRE2, libyaml, GMP, libz, libssl or libcrypto,
still gzips its responses, and peaked at 17.4 to 17.5 MiB of RSS under load
at the 8 MiB heap on an M4 Mac mini, against 19.8 to 19.9 MiB for the
default build. The flags are opt-in: a default build still links libz and
OpenSSL through Crystal's own `HTTP` and `OpenSSL` code. Amber's cookie and
session cryptography runs on Beryl, whose hashes and ciphers use the
processor's own instructions on Apple Silicon, Linux AArch64 and x86-64.
Every regex in Amber runs on Mica, and `logging.severity` from the
environment file now sets the level the app logs at. The new
`docs/guides/performance.md` (#1471) gives the patterns and settings that
make an app fast and small from the first build, each with its measurement.

**`logging.severity` from the environment file now sets the level the app
logs at (#1461).** Amber read and validated `logging.severity` (and
`AMBER_LOGGING_SEVERITY`) but nothing applied it to Crystal's `Log`, so
every app logged at `info` whatever the file said, and at `debug` in
development the request logger wrote nothing. The new
`Amber.settings.logging.apply_severity_to_log` binds every `Log` source to
that level; the app calls it once at boot, before `Amber::Server.start`.
Amber CLI 2.0.15 writes the call into `src/<app>.cr`. An app generated
earlier adds the one line itself:

```crystal
Amber.settings.logging.apply_severity_to_log
Amber::Server.start
```

- The vendored copy of Mica under `src/amber/vendor` (`Amber::Mica`) moves to
  amberframework/mica `37e8b019` (amberframework/mica#29, faster Inflate),
  pinned by commit and per-file sha256 in `MICA_VENDORED.json`. Only
  the decoder (`mica/deflate/inflater.cr`) changed: it inflates the same
  bytes faster.

**`Amber::Pipe::Compression` now compresses with Mica, in Crystal, and an app
built with `-Dwithout_zlib` links no libz.** The pipe gzips and deflates
responses with a pinned copy of
[Mica](https://github.com/amberframework/mica)'s DEFLATE encoder under
`src/amber/vendor` (`Amber::Mica`, pinned by commit and per-file sha256 in
`MICA_VENDORED.json`). Before, a build with `-Dwithout_zlib` compiled the
pipe to a pass-through; now it compresses the same way with or without the
flag. A request body with a `Content-Encoding` is still answered `415` before
any pipe runs. `scripts/check_linkage.sh` builds the probe app with the flag
and checks that it links no libz, answers a gzip response and refuses a
gzip-encoded request body.

Behavior changes in `Amber::Pipe::Compression`:

- The compressed bytes are Mica's, not zlib's. They decode in every gzip and
  zlib decoder, and over the benchmark corpus they are 0.04% smaller than
  zlib's at level 6; they are not byte for byte what
  `HTTP::CompressHandler` writes.
- A gzip response carries no modification time (the header field is 0), so
  the same body always compresses to the same bytes. It used to carry the
  time of the first write.
- `idle_compressors:` and the `pool` getter are gone. Each response's
  compressor takes its tables (about 270 KB) from `malloc`, outside the
  collected heap, and frees them when the response closes; there is no pool
  to size. `Amber::Pipe::Compression.new(level: 6)` and a subclass with an
  empty body, as Amber CLI generates, need no change.

**Amber's own cryptography now runs on Beryl, in Crystal, and an app built
with `-Dwithout_openssl` links no OpenSSL.** Cookie signing and encryption,
flash, encrypted files and COSE call a pinned copy of
[Beryl](https://github.com/amberframework/beryl) under `src/amber/vendor`
(`Amber::Beryl`, pinned by commit and per-file sha256 in
`BERYL_VENDORED.json`). OpenSSL remains only for TLS: the HTTPS listener and
SMTP STARTTLS. An app that sits behind a proxy which terminates TLS can be
built with `crystal build -Dwithout_openssl`; it then links neither libssl
nor libcrypto, and turning on `server.ssl` or mailer `use_tls` in such a
build raises `Amber::Exceptions::TLSNotCompiledIn`, which names the flag.

- The vendored copy of Beryl under `src/amber/vendor` (`Amber::Beryl`) moves from
  `6eef806d` (B2, portable code) to amberframework/beryl `7d678c08`
  (F1, amberframework/beryl#3, and F2, amberframework/beryl#4), pinned by
  commit and per-file sha256 in `BERYL_VENDORED.json`. SHA-2, HMAC, AES-GCM,
  ChaCha20-Poly1305 and XChaCha20-Poly1305 run on the processor's SHA, AES,
  carry-less multiply and vector instructions on Apple Silicon, Linux AArch64
  and x86-64, and on portable code elsewhere; Beryl measures every hash, HMAC
  and AEAD at least as fast as OpenSSL 4.1.0 on an Apple M1 Max. The bytes
  each one produces are unchanged.

**New encrypted message format (version 2).** `MessageEncryptor` (encrypted
cookies, encrypted sessions, `FileEncryptor`) now writes
`"AMB2" | nonce (24 bytes) | ciphertext | tag (16 bytes)`:
XChaCha20-Poly1305 under a key derived from the secret with HKDF-SHA256.
Version 1 values (AES-256-CBC with HMAC, written by every earlier release)
are still read under the current secret and each previous secret, so
existing cookies and encrypted files keep working and are rewritten in
version 2 the next time they are saved. A version 2 value is 12 bytes
shorter than version 1 for most messages. An app that must roll back to an
earlier release after writing version 2 values will find those values
unreadable there; visitors are then signed out once.

**Behavior change: the signing digests are a closed set.** `MessageVerifier`
and `MessageEncryptor` accept `:sha256` (the default), `:sha384`, `:sha512`
and `:sha1` (for cookies signed by Amber 1). Any other digest name raises
`ArgumentError` at construction; before, the name went to OpenSSL at the
first signature. `MessageEncryptor` accepts `"aes-256-cbc"` as the cipher
of version 1 messages and raises `ArgumentError` for any other.

COSE (`Amber::Schema::COSE`) is unchanged on the wire: the same
ChaCha20-Poly1305 bytes as before, checked against messages captured from
the OpenSSL implementation.

- **Every regex in Amber runs on Mica**, the default `Regex` engine of
  crystal-alpha from 1.21.0-incremental-6. `HTML.encode_entities` and
  `Amber::Markdown::HTMLEntities::Encoder` are removed: the encoder called
  `Hash#key`, which Crystal does not have, so no program that called it ever
  compiled, and its pattern for surrogate pairs is one Mica refuses to
  compile. `HTML.decode_entities` and `HTML.decode_entity` are unchanged.
- CI checks every regex in `src` and `spec` against Mica's dialect
  (`scripts/check_regex_literals.cr` from amberframework/mica, pinned by
  commit), so a pattern with lookaround, a backreference, an atomic group or
  a possessive quantifier fails the build.

## 2.0.0-beta.13 (2026-11-22)

**Security: a form's `charset` is held to the WHATWG Encoding Standard.**
Through beta.12 the `charset` a client declared on a URL-encoded form went
straight to iconv, so on Linux a request could open any converter glibc
ships by naming it. From this release only the labels of the WHATWG Encoding
Standard (https://encoding.spec.whatwg.org/#names-and-labels) are accepted,
whatever their letter case, and each opens the one decoder Amber maps it to.
A form with any other `charset` (`UTF-7`, `ISO-2022-CN-EXT`, an empty or
oversized name, and the standard's `replacement`, `x-user-defined`,
`windows-1255` and `windows-1258` encodings) is answered with `415 Unsupported Media Type` before its body is
read; it raises `Amber::Exceptions::UnsupportedCharset`, a `BadRequest`, and
a schema parse reports it as `unsupported_media_type`. A UTF-8 label parses
the form directly, with no converter. Multipart and JSON bodies never took
an encoding name from the request and are unchanged.

## 2.0.0-beta.12 (2026-11-22)

**Behavior change: `store: signed_cookie` now keeps the session in a cookie.**
`signed_cookie` is the default store in every generated app. Through beta.11
every store, `signed_cookie` included, quietly kept sessions in the server's
memory. From beta.12 a `signed_cookie` or `encrypted_cookie` app keeps the
session in the visitor's cookie and nothing on the server, so session values
travel with every request and must fit in a 4,096-byte cookie (a larger
session raises `Amber::Exceptions::CookieOverflow`), the visitor can read (but
not change) a `signed_cookie` session, and `regenerate_session!` does nothing.
An app that needs server-side sessions sets `store: adapter` under `session:`
(or `AMBER_SESSION_STORE=adapter`).

- Asset tags are rendered once per manifest. `stylesheet_link_tag`,
  `javascript_include_tag`, `image_tag` and `favicon_tag` for a logical path
  without extra attributes, and `javascript_importmap_tag`, keep their HTML in
  the manifest's `RenderedTags` and return it on later calls without
  allocating. A generated layout's three tags cost 6.9 KB per page before. A
  manifest reloaded in development starts empty, a missing asset stores
  nothing, and each kind of tag stores at most 1,024 entries.
- `Amber::Pipe::Compression` gzips or deflates responses for clients that
  accept it, with the same bytes as Crystal's `HTTP::CompressHandler`. Its zlib
  streams come from `malloc`, outside the collected heap, and are reused through
  a small pool (`idle_compressors:`, 4 by default), where `HTTP::CompressHandler`
  allocates about 270 KB from the collected heap for every compressed response.
  Like the `CompressedResponsePipe` that Amber CLI generates, it answers range
  requests uncompressed and adds `Vary: Accept-Encoding`; a generated app can
  make that class a subclass of it. Request bodies are untouched: a compressed
  request body is still answered `415` before any pipe runs.
- `Amber::Pipe::Logger` allocates nothing when the log level filters its lines
  out. At the default `info` level it used to build every debug line before
  `Log` dropped it, parse the params, and create a session, about 11.8 KB per
  request while writing nothing. When it does write, each line is built inside
  the `Log` block and headers are read in place.
- A request with a compressed body is answered `415 Unsupported Media Type`,
  with `Accept-Encoding: identity` and `Connection: close`, before routing or
  any pipe reads its body. Crystal before 1.21.1 inflates gzip and deflate
  request bodies inside `HTTP::Server` with no size limit
  ([GHSA-jfq5-c3x6-w7jj](https://github.com/crystal-lang/crystal/security/advisories/GHSA-jfq5-c3x6-w7jj)),
  so a 1 MiB gzip body could become 1 GiB. Amber recognizes a compressed body
  in both forms a compiler can hand it:
  - a `Content-Encoding` header naming any coding other than `identity`
    (Crystal 1.21.1 and later, and crystal-alpha with the advisory backport,
    leave the header and the raw body in place);
  - a body that `HTTP::Server` already wrapped in `Compress::Gzip::Reader`,
    `Compress::Deflate::Reader` or `Compress::Zlib::Reader` (Crystal before
    1.21.1 does this for `gzip` and `deflate` and deletes the
    `Content-Encoding` header). That reader inflates only as it is read, so a
    refused body is never inflated.

  The protection covers gzip and deflate bodies on every compiler, and any
  other coding that arrives with its `Content-Encoding` header. An app that
  accepts compressed uploads sets `params.accepts_encoded_request_bodies: true`
  (or `AMBER_PARAMS_ACCEPTS_ENCODED_REQUEST_BODIES=true`) and must bound the
  body itself; on Crystal before 1.21.1 that body arrives as a reader that
  inflates without limit.
- `Amber::Pipe::Static` honors `q` values in `Accept-Encoding`. It used to serve
  the precompressed `.gz` file to `Accept-Encoding: gzip;q=0`, because the
  standard library only looks for the word `gzip`. `Static.accepts_gzip?` holds
  the rule: the `gzip` or `x-gzip` entry decides, then `*`.
- `Amber::Pipe::Flash` writes the session only when the flash has messages, or
  when it must clear a flash the session still holds. It used to write
  `session["_flash"] = "{}"` on every response, so every request without a
  session cookie created a session. With the memory adapter, each such request
  kept about 413 bytes for two weeks: a `:web` route served to clients that do
  not send cookies back grew from 441 MiB after 30 s to 858 MiB after 90 s.
- `session.store` is honored. `signed_cookie` (the default) and
  `encrypted_cookie` keep the session in the visitor's cookie and nothing on
  the server; `adapter` (new) and `redis` keep it on the server through
  `session.adapter`. Every store used to build the memory adapter session.
  Apps that relied on server-side sessions, for example to call
  `regenerate_session!`, set `store: adapter`.
- `MemorySessionAdapter` keeps at most `session.max_memory_sessions` sessions
  (default 10,000, `AMBER_SESSION_MAX_MEMORY_SESSIONS` overrides it) and drops
  the session used longest ago when it is full. `validate!` rejects a value
  below 1. It used to have no limit.

## 2.0.0-beta.11 (2026-11-20)

- `respond_with` accepts a `NamedTuple` as documented
  ([#1425](https://github.com/amberframework/amber/issues/1425)). It used to
  build a hash with `Symbol` keys, so the call did not compile. The tuple now
  becomes `Hash(String, JSON::Any)` through its JSON form, which also accepts
  `Int32`, arrays and nested tuples as values. `scripts/check_linkage.sh` answers
  one route this way, so the path stays free of PCRE2.
- `respond_with` accepts any JSON-serializable `Hash` (`Hash(String, String)`,
  `Hash(Symbol, Int32)` and the like). It used to accept only
  `Hash(String, JSON::Any)`, and any other hash failed to compile with
  "can't use NamedTuple(T) in unions yet".
- `respond_with` honors `q` values in the `Accept` header and chooses among the
  formats the response schema declares. `Accept: application/cbor;q=0,
  application/json` used to answer CBOR, and a JSON-only schema answered `406`
  to `Accept: application/cbor, application/json;q=0.5` though JSON was acceptable.
- `server.gc_initial_heap_mib` (default 0) grows the garbage collector's heap to
  that many MiB in every server process before it takes requests;
  `AMBER_SERVER_GC_INITIAL_HEAP_MIB` overrides it and `validate!` rejects a
  negative value ([#1452](https://github.com/amberframework/amber/pull/1452)).
  0 keeps the collector's own starting size, so existing apps see no change.
  Amber CLI 2.0.11 writes 16 into every generated environment file. That is the
  smallest starting heap that kept a generated app's POST p50 at or below
  beta.10's, and it adds about 8 MiB of peak memory.
- A default `amber new -d sqlite` app links no PCRE2. With Grant 0.24.0 and
  asset_pipeline 0.38.0, which keep `Regex` off their default require paths, the
  app Amber CLI 2.0.11 generates shows no `libpcre2` in `otool -L` and no `pcre2_`
  symbol in `nm`, before and after `amber generate scaffold` adds a Grant model.
  Amber CLI CI checks this on macOS and Linux.

## 2.0.0-beta.10 (2026-11-07)

- A JSON API built on Amber no longer reaches `Regex` on its request path, so
  with the router and fixed-pattern changes it links no PCRE2 on stock Crystal.
  The `Cookie` header, form keys, form values, named schema formats, backtrace
  frames and `String#url?` are read by hand-written checks (`HeaderParser`,
  `FormKey`, `Amber::Support::TextFormats`). Each format check is tested against
  the pattern it replaced on 40,000 generated strings.
- An app that uses a pattern still links PCRE2, and only that app: `pattern:`,
  `filename_pattern:` and a custom `format:` on a schema field, a `Regex` passed
  to `Validator::Pattern`, `Validator::Format` or `Pipe::CORS`, and the
  locale-based `String` checks.
- `Validator::Format` with `FormatType::URL` answers in linear time. The pattern
  it replaces raised `Regex::Error` (match limit exceeded) on short crafted input.
- One malformed cookie no longer fails a request: that pair is left out and the
  others are kept. Otherwise the parser finds the same cookies as
  `request.cookies`, tested on 60,000 generated headers.
- The exception page colors source lines with `ExceptionPage::CodeColoring`, so
  apps no longer compile the compiler's lexer.
- **Breaking:** a `Set-Cookie` header on a request is ignored. Browsers never send
  one, and specs that replayed response headers as a request must send `Cookie`.
- **Breaking:** `Validator::Format::PATTERNS` is removed.
  `Backtracer::Configuration#app_dirs_pattern` becomes the prefix list
  `list_of_app_directories`, and `modules_path_pattern` becomes the prefix
  `modules_directory`. `Pipe::CORS#origins` holds strings and
  `OriginRule` procs. `CORS.new` accepts `CORS::OriginType` as before, and now
  also `Array(String)`, the form that links no regex engine. The pipe copies its
  origin list when it is built, so add origins before that; `cors.origins << regex`
  no longer compiles.
- **Breaking:** a phone number or the host of a `FormatType::URL` value accepts
  ASCII digits only. The old patterns also accepted other scripts' digits (`١٢`).
- The schema examples move from `src/amber/schema/examples` to `examples/schema`,
  so `require "amber"` no longer compiles them.
- Route parameter constraints are typed rules instead of `Regex`, and the
  router (`src/amber/router/**`) uses no regular-expression engine; a program
  that uses only `Amber::Router::RouteSet` no longer links libpcre2. A route
  names a preset (`{"id" => :numeric}`; also `:uuid`, `:slug`, `:alpha`,
  `:alnum`, `:hex`), passes a rule from `Amber::Router::ParamConstraints`
  (`NUMERIC.with_length(3)`, `OneOf.new("draft", "published")`,
  `CharacterRun.new(...)`, `Custom.new("label") { |segment| ... }`), or its own
  type that includes `Amber::Router::ParamConstraint`. **Breaking:** a
  `Regex` constraint no longer compiles; replace `{"id" => /\d+/}` with
  `{"id" => :numeric}` (see "URL Parameter Constraints" in
  `docs/guides/routing.md`). A rule judges the whole segment, so
  `{"cart" => /\d\d\d/}`, which matched `he110`, becomes
  `NUMERIC.with_length(3)`, which matches only three digits.
  `CONSTRAINT_PRESETS` now holds these rules, and an unknown preset symbol
  raises `ParamConstraints::UnknownPresetError` when routes are drawn. The
  character presets are ASCII: `:numeric` no longer matches other scripts'
  digits (`١٢`), which the Unicode-aware `\d` did, and the response-extension
  check no longer finds `.json` before a trailing newline, which `$` did.
- Rule-checked lookups are 15 to 27% faster, and a hit allocates 32 bytes less,
  because the built-in rules read the path in place
  (`benchmarks/router_constraints.cr`).
- `HTTP::Request#port` reads a `Host` header without a regex. A bare IPv6
  literal (`[::1]`) or an unbracketed one (`::1`) no longer reports port 1, and non-digit or out-of-range
  port text falls back to the request URI's port instead of raising or
  reading a prefix.
- `Amber::Router::Router::PATH_EXT_REGEX` is replaced by `PATH_EXTENSIONS`
  (`[".html", ".json", ...]`, from `Content::TYPE`), and
  `Amber::Router::Params::TYPE_EXT_REGEX`, an unused alias of
  `Amber::Support::MimeTypes::TYPE_EXT_REGEX`, is removed.

## 2.0.0-beta.9 (2026-11-06)

This release adds trusted proxies, a UNIX socket listener and a security headers
pipe, and ships Amber's rules and guides with the framework. See
`RELEASE_NOTES_V2_BETA9.md`.

- `server.trusted_proxies` decides the client IP and HTTPS from listed proxies
  only; applications can listen on a UNIX socket (#1415).
- `Amber::Pipe::SecurityHeaders`, with a typed `security_headers` section (#1422).
- `.amber-lsp/packs/amber_v2.yml`: rule pack and session guidance for amber-lsp.
- `.amber-lsp/api/amber.yml`: API card for `amber-lsp lookup`. Public params and
  validator methods declare concrete return types.
- `ai_docs` installs every guide in `docs/guides/`, with an `amber-guides` skill.

## 2.0.0-beta.8 (2026-11-01)

This release builds on every Crystal version that `shard.yml` declares and
lets an application set its own cache policy for static files. See
`RELEASE_NOTES_V2_BETA8.md`.

- Compile on Crystal 1.20 again (#1434, #1436). Beta.7 passed `writable:`
  to `IO::Memory.new`, a parameter name that Crystal 1.21 introduced; both
  calls pass the read-only flag positionally. CI now runs the suite on
  Crystal 1.20.0, the lowest version `shard.yml` declares.
- `Amber::Pipe::Static` keeps a `Cache-Control` that an earlier handler set,
  and takes its own policy from a protected `#cache_control(request_path)`
  hook that a subclass can override (#1435, #1437). Without either, the
  policy is the same as before: immutable for a 16 to 64 character hex
  fingerprint, otherwise the configured static `Cache-Control` or
  `no-cache`. A configured `Cache-Control` is matched in any spelling
  `HTTP::Headers` accepts.
- `Amber::Pipe::Static` adds asset headers to GET and HEAD requests only, the
  methods it serves; a POST to a static path no longer receives an immutable
  `Cache-Control` on its 405 or on the response of a following handler.

## 2.0.0-beta.7 (2026-11-01)

This release makes the fixes that AgentC applications carried on a fork
part of Amber itself, so those applications can depend on an official
release again. It also routes `.md` paths to their declared routes again,
bounds request parameter parsing, and adds a credentials directory reader.
See `RELEASE_NOTES_V2_BETA7.md`.

- Route a path that ends in a response extension to the route that declares
  that extension in its own path. `get "/projects/:id/insights/overview.md"`
  answers `/projects/7/insights/overview.md` again instead of a later
  `get "/*"` catch-all, which beta.6 reached after removing `.md`. A path no
  route declares still has its extension removed first, so `/users/1.json`
  matches `/users/:id`.
- Restore the request body after Amber parses an urlencoded form, so a
  controller behind the CSRF pipe can still read `request.body`. The bytes
  the bounded parse read are handed back, so the copy never exceeds
  `params.max_form_body_bytes`.
- Delete upload tempfiles when the request finishes. `Amber::Pipe::Pipeline`
  releases them in its `ensure`; to keep an upload, call
  `Amber::Router::File#move_to` or `#retain!` during the action (see
  Security below).
- Restore a multipart request body up to `params.max_multipart_restore_bytes`
  (8 MiB by default, `0` turns it off, `AMBER_PARAMS_MAX_MULTIPART_RESTORE_BYTES`)
  by copying it to a tempfile in the private upload directory, which is
  deleted with the uploads. A body is copied only when its declared
  `Content-Length` is within both that limit and
  `params.max_multipart_body_bytes`; a larger body, or one without
  `Content-Length`, stays drained after parsing.
- Load custom config sections without deserializing through every
  `YAML::Serializable` type. `AppConfig#custom_configs` now holds each
  section as raw YAML (`Hash(String, String)`), `AppConfig#custom` reads it as
  the requested type or returns the registered default, and an unregistered
  key raises `Amber::Exceptions::ConfigurationError`. An app whose Grant models
  have UUID columns compiles with custom config again.
  `Amber::Configuration.load_custom_from_yaml` is removed.
- Add `Amber::Configuration::CredentialsDirectory` and
  `Amber::Configuration.register_credentials`, which read a systemd-style
  `$CREDENTIALS_DIRECTORY` (one file per credential) into a typed, registered
  settings section. Each read opens the directory once and works relative
  to that open directory. The reader rejects path traversal, symlinks
  outside the directory, FIFOs and other special files, unreadable files,
  files over a per-file cap, and reads over a total cap with named errors,
  opens each file without following a final symlink, and never logs or
  quotes values. A section reads only the files its type declares. Windows
  raises `CredentialsDirectoryUnsupported`.
- Extend the `AMBER_{SECTION}_{KEY}` environment override pass to registered
  custom sections, including nested sections that are nil or absent and
  nil-valued fields. Values follow the field's type as in the built-in pass,
  and a section is rebuilt from the YAML or credentials it was loaded from,
  or from its registered default: each field Amber can write as YAML keeps
  the default's value, and any other field takes its declared default. A
  `Hash` field takes a variable for each key it already holds.
- Raise a `ConfigurationError` when a credentials section is also defined in
  the environment YAML file.

- Load settings at first use instead of while `amber` is required (#1424),
  so a custom section registered in `config/initializers` reads its YAML
  value, and `config/application.cr` can still set `Amber.path` and
  `Amber.env`. Amber colors its own log lines from `logging.colorize`
  through `Amber::Support::LogColor` and leaves the process-wide
  `Colorize.enabled` flag alone.
- Build without compiler warnings (#1421): the 25 deprecation warnings from
  `Params#validation` are gone. Specs that compile fixture programs use the
  compiler named by `CRYSTAL`, otherwise `crystal-alpha`.
- The ecosystem agent context names Micrate, Gemma and Mica, and the schema
  guide shows XML through Mica (#1417).
- Spec sockets write to their own `IO::Memory` instead of `STDOUT`, so a
  closing test socket no longer closes the spec runner's output (#1431).

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
  their limit. JSON and other document bodies read for schemas or `params`,
  including bodies read by a parser registered with
  `ParserRegistry.register_body_parser`, are bounded by
  `max_document_body_bytes` (8 MiB); a longer body is answered with
  `400 parameter_limit_exceeded`.
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
  plain `params` readers see the same key, value, count and depth limits
  as schema contracts: a key nested deeper than `max_nesting_depth` is
  answered with `400 Bad Request`. Bracketed array indices are checked
  where a schema parser reserves array slots for them, so a form that
  names records by id in brackets, such as `users[1700000][name]`, still
  reads as ordinary `params`.
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
- A rejected request body is remembered on the request
  (`HTTP::Request#guard_body_read`): every later read of `params`,
  `form_params`, or a schema contract for that request raises the same
  error, so a caller that catches it never sees a parse of the bytes left
  in the stream. Rejections raised after the body was read (such as a CBOR
  or COSE decoding error) are remembered the same
  way, and a cached parse is not served once the body is rejected. Schema
  parsers check each key, and reserve its array slot, before they read or
  parse its value, so a rejected key never loads an upload into memory.
  Each request's schema data is parsed once and reused, so repeated
  schema reads charge its limits once. Upload cleanup continues past a
  file that fails to close or delete, keeps the original error, and
  retries a failed delete when a later request finishes. A schema's
  declared media types are checked on every schema read, including one
  served from that cached data. CBOR and COSE bodies are read under
  `max_document_body_bytes` as well as their decoders' own limits, checked
  before a declared length is allocated; long values are read, and arrays
  grow, as their bytes arrive. Malformed JSON in a schema read is answered with
  `400 Bad Request` and stays rejected for later reads of that request.
- URL-encoded bodies that declare a `charset` are decoded to UTF-8 while
  they stream, as Crystal's `HTTP::Request#form_params` does; an unknown
  charset is answered with `400 Bad Request`. `max_form_body_bytes` counts
  the raw bytes before decoding.
- Error pages escape what they show of the request: the error response's
  type is chosen by Amber (JSON, HTML or plain text, from the first
  `Accept` entry without its parameters) rather than echoed from the
  header, the production HTML error page HTML-escapes the error message,
  and the development
  exception page escapes the method, path and title. A development error
  page for a rejected query or form shows the request-line method and no
  query parameters, so the 400 is not raised again while rendering.
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

## 2.0.0-beta.6 (2026-11-01)

This release takes libxml2 out of every Amber V2 application. XML request
bodies become opt-in, served by Mica, a pure-Crystal parser, so a static
build of an Amber V2 + Grant application no longer links libxml2 or the
liblzma it brings. See `RELEASE_NOTES_V2_BETA6.md` for measurements.

- Remove the libxml2-backed XML request parser (#1414). XML bodies are
  answered with 415 unless the application registers a parser.
- Add `ParserRegistry.register_body_parser` so an application opts in to
  another body format with one call at boot (#1414).
- Pin CI: Crystal 1.22.1 tarballs checked by sha256, actions by full commit
  SHA, the CircleCI image by digest, dependencies from a committed
  `shard.lock` with `--frozen`, and a crystal-alpha job (#1420).
- Fix specs that built HTTP messages Crystal 1.22 rejects (#1418).

### Breaking Changes

#### XML request parsing removed

Amber V2 parses request bodies as JSON and form data
(`application/x-www-form-urlencoded`, `multipart/form-data`), plus the
existing bounded CBOR and COSE schema formats. The XML request parser added
during the beta line is gone:

- `Amber::Schema::Parser::XMLParser`, its example, and its README are removed.
- A request whose `Content-Type` is `application/xml`, `text/xml`, or any
  `+xml` type is answered with `415 Unsupported Media Type`
  (`unsupported_media_type`), including when a schema lists that media type in
  `content_type`.
- A standalone `ParserRegistry.parse_request` call no longer sniffs a body
  that starts with `<` as XML; it returns an empty hash, as it does for any
  other unrecognized body.
- Amber no longer requires Crystal's `xml` module, so applications built on
  Amber stop linking libxml2.

XML request bodies are opt-in. 415 stays the default answer; an application
turns XML on explicitly, for example with Mica, a pure-Crystal XML parser
(`amberframework/mica`), which reads a body into the same fields a JSON object
gives. Add it to the application's `shard.yml`:

```yaml
  mica:
    github: amberframework/mica
    version: 0.1.0
```

Upgrade: an application that accepted XML bodies through the Schema API either
moves those endpoints to JSON or registers its own XML parser once at boot and
keeps `application/xml` in the schema's `content_type` list:

```crystal
# config/initializers/request_body_parsers.cr
require "mica/xml/fields"

{"application/xml", "text/xml"}.each do |media_type|
  Amber::Schema::Parser::ParserRegistry.register_body_parser(media_type) do |body|
    Mica::XML::Fields.read(body)
  end
end
```

A registered parser that raises answers the request with
`400 invalid_request_body`.

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
