# Amber 2.0.0-beta.14

Amber 2.0.0-beta.14 lets an app drop libz and OpenSSL, runs its cryptography
on Beryl at hardware speed, runs every regex on Mica, and applies
`logging.severity` from the environment file.

## An app can link no libz and no OpenSSL

Built with `-Dwithout_zlib -Dwithout_openssl`, an `amber new -d sqlite` app
with a scaffold, on Amber CLI 2.0.15, links none of PCRE2, libyaml, GMP,
libz, libssl or libcrypto (`otool -L` and `nm -u` both show none). It still
gzips its responses, accepts a form `POST`, and refuses a gzip request body
and a `charset=UTF-7` form with `415`. Under load at the 8 MiB starting heap
it peaked at 17.4 to 17.5 MiB of RSS on an M4 Mac mini, against 19.8 to
19.9 MiB for the default build of the same app.

The flags are opt-in. A default build still links libz and OpenSSL, because
Crystal's own `HTTP` and `OpenSSL` code requires them.

- `-Dwithout_zlib`: `Amber::Pipe::Compression` gzips and deflates with a
  pinned copy of Mica's DEFLATE, in Crystal, in every build. Grant's
  compressed columns and asset_pipeline's precompressed assets and stored
  pages use Mica too. `idle_compressors:` and the compressor pool are gone;
  a gzip response carries no modification time.
- `-Dwithout_openssl`: cookie signing and encryption, flash, encrypted files
  and COSE run on a pinned copy of Beryl. OpenSSL remains only for TLS, so
  the flag suits an app whose TLS ends at a proxy; in such a build
  `server.ssl` and mailer `use_tls` raise
  `Amber::Exceptions::TLSNotCompiledIn`.

## Cryptography on Beryl, at hardware speed

Encrypted cookies, encrypted sessions and `FileEncryptor` now write message
format version 2 (XChaCha20-Poly1305 under an HKDF-SHA256 key). Version 1
values are still read under the current and every previous secret and are
rewritten in version 2 on their next save. An app that rolls back to an
earlier beta after writing version 2 values signs its visitors out once.
`MessageVerifier` and `MessageEncryptor` accept `:sha256`, `:sha384`,
`:sha512` and `:sha1`; any other digest raises `ArgumentError` at
construction.

Beryl is pinned at amberframework/beryl `7d678c08`. Its hashes, HMAC and
AEADs run on the processor's SHA, AES, carry-less multiply and vector
instructions on Apple Silicon, Linux AArch64 and x86-64, and Beryl measures
every one at least as fast as OpenSSL 4.1.0 on an Apple M1 Max.

## Every regex runs on Mica

Every regex in Amber compiles on Mica, the default `Regex` engine of
crystal-alpha from 1.21.0-incremental-6, and CI checks each one.
`HTML.encode_entities` and `Amber::Markdown::HTMLEntities::Encoder` are
removed: no program that called them ever compiled.

## `logging.severity` sets the log level (#1461)

`logging.severity` (and `AMBER_LOGGING_SEVERITY`) was read but never
applied, so every app logged at `info`. An app now applies it once at boot:

```crystal
Amber.settings.logging.apply_severity_to_log
Amber::Server.start
```

Amber CLI 2.0.15 writes that line into `src/<app>.cr`. An app generated
earlier adds it after its last `require`.

## Performance guide

`docs/guides/performance.md` (#1471) gives the patterns, tools and settings
that make an Amber app fast and small from its first build, each with the
measurement it rests on.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.15 for new apps; it pins Amber `v2.0.0-beta.14`, Grant
`v0.26.0` and asset_pipeline `v0.39.0`. For an existing app, pin the three
release commits in `shard.yml`, run `minecart update amber grant
asset_pipeline`, add the `apply_severity_to_log` line, and run
`amber setup:agent`. Grant 0.26.0 writes encrypted attributes in format
version 2, which Grant 0.25.1 cannot read, so roll back only before new
values are written.
