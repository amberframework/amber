# Amber 2.0.0-beta.15

Amber 2.0.0-beta.15 makes TLS opt-in, so a default app on crystal-alpha links
no OpenSSL without a build flag, and compresses responses with Brotli when the
client asks for it.

## TLS is opt-in: `require "amber/tls"`

Amber no longer compiles its TLS listener into every app, and its own files
require `http/server` instead of `http`, so Amber brings in no
`HTTP::Client`. On crystal-alpha 1.22.3-incremental-1, whose `http/server`
leaves TLS out unless a program asks for it, an `amber new -d sqlite` app with
a Post scaffold links none of libssl, libcrypto, libz,
libiconv or PCRE2 without any build flag (`otool -L` shows none, and `nm -u`
shows no `SSL_`, `BIO_`, `ERR_`, `X509_` or `EVP_` import). It serves `GET /`,
accepts the scaffold's form `POST`, passes its 12 specs, and peaked at 18.2
MiB of RSS under load at the 8 MiB starting heap on an M4 Mac mini, against
20.0 MiB for the beta.14 app built by the same compiler.

An app that serves HTTPS itself (`server.ssl`) or sends mail over SMTP
STARTTLS (mailer `use_tls`) adds one line to `config/application.cr`, right
after `require "amber"`:

```crystal
require "amber/tls"
```

`amber new --tls` writes it. Without it, a server whose settings ask for TLS
stops at start, before it forks or binds, with
`Amber::Exceptions::TLSNotCompiledIn`, whose message names
`require "amber/tls"`. A `--tls` app served HTTPS with a self-signed
certificate (`curl -k` 200); it links OpenSSL, and peaked at 18.9 MiB over
plain HTTP and 32.2 MiB under 32 concurrent HTTPS connections.

On stock Crystal, `http/server` still requires `openssl`; `-Dwithout_openssl`
keeps its meaning there, and it cannot be combined with `require "amber/tls"`.

## Brotli content coding

`Amber::Pipe::Compression` offers Brotli, gzip and deflate and picks the one
the client accepts best, with `Accept-Encoding` q-values honored (RFC 9110,
section 12.5.3); on a tie Brotli comes first. Brotli comes from a pinned copy
of Mica's pure-Crystal encoder at quality 5, so an app links no libbrotli
(`Compression.new(brotli_quality: nil)` offers gzip and deflate only). A body
shorter than 1,024 bytes is sent without a content coding.
`Amber::Pipe::Static` serves a precompressed `file.br` as well as `file.gz`.
In a generated app, `GET /posts/new` with `Accept-Encoding: br` comes back
with `Content-Encoding: br`. A page answered from asset_pipeline's page cache,
such as the generated home page, is stored as gzip and identity only, unless
the app is built with `-Dasset_pipeline_brotli`.

## Vendored Mica and Beryl

- Mica moves to amberframework/mica `84812fd1` (component `compression`): the
  Brotli writer sizes its tables to a short body (amberframework/mica#34),
  Brotli decoding is at least as fast as libbrotlidec 1.2.1
  (amberframework/mica#35), and the Deflate and Zlib readers stop at the end
  of the stream (amberframework/mica#38). The encoder stays the Z6b port of
  libbrotlienc 1.2.1.
- Beryl moves to amberframework/beryl `b1df8cc1`: the hashes, HMAC, HKDF and
  AEADs Amber calls run with the processor's Data Independent Timing mode on
  (amberframework/beryl#9) and give the same bytes. The copy also carries the
  public-key code (F3b) and the x86-64 timing fix (amberframework/beryl#18),
  which Amber does not call.

Both are pinned by commit and per-file sha256.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.16 for new apps; it pins Amber `v2.0.0-beta.15`, Grant
`v0.26.0` and asset_pipeline `v0.40.0`, and `amber new --tls` makes an app
that serves HTTPS itself. For an existing app, pin the Amber and
asset_pipeline release commits in `shard.yml`, run
`minecart update amber asset_pipeline`, and, if the app serves HTTPS itself
or sends mail with `use_tls`, add `require "amber/tls"` after
`require "amber"` in `config/application.cr`.
