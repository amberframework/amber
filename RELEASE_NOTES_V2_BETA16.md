# Amber 2.0.0-beta.16

Amber 2.0.0-beta.16 runs its TLS on Beryl, Amber's own TLS 1.3 written in
Crystal. An `amber new` app links no OpenSSL with no flag and no setting,
whether it serves HTTPS itself (`--tls`), sends mail over TLS, or talks to
PostgreSQL or MySQL over TLS. TLS 1.3 is the only version spoken.

This release ships together with Grant 0.28.0, asset_pipeline 0.40.1,
crimson-knight/crystal-mysql on Beryl, Beryl 0.2.1 and Amber CLI 2.0.17,
which pins all of them.

## HTTPS and mail on Beryl

`require "amber/tls"` (written by `amber new --tls`) now serves HTTPS from
Beryl: the PEM certificate chain in `server.ssl.cert_file` and the private
key in `server.ssl.key_file` (P-256, RSA or Ed25519), SNI, and ALPN
`http/1.1`. The settings are the same as in beta.15; nothing in `config/`
changes. A client whose handshake fails ends only its own connection.

The mailer's STARTTLS (`use_tls`) and, new, implicit TLS
(`use_implicit_tls`, port 465) verify the mail server's chain against the
Mozilla roots, or against `ca_certificates_file` (new), and its host name.

Measured on an M1 Max and an M4 Mac mini with a scaffolded `--tls` app under
32 keep-alive HTTPS connections: peak RSS 25.5 to 25.8 MiB with Beryl
against about 31 MiB with OpenSSL, and requests per second at or above the
OpenSSL build on both machines.

## TLS 1.3 only

A browser, client, mail server or database that cannot speak TLS 1.3 is
refused with an error that names the requirement. Every current browser,
curl, Go, PostgreSQL 12 and later (`ssl_min_protocol_version = 'TLSv1.3'`)
and MySQL 8.0 and later speak it.

## Databases on Beryl (Grant 0.28.0, crystal-mysql)

Grant's PostgreSQL driver and crimson-knight/crystal-mysql connect over Beryl
TLS 1.3: `sslmode` `require`, `verify-ca` and `verify-full` for PostgreSQL
(with SCRAM-SHA-256-PLUS channel binding), and `ssl-mode` for MySQL. Without
`sslrootcert`, the chain is checked against the system roots (the file
`SSL_CERT_FILE` names, else the operating system's bundle). Private
certificate authorities whose certificates carry no authority key
identifier verify, as with Go and OpenSSL. `pg_dump` and `psql`, run by
Grant's structure dump and load, verify the server with the same settings.

## Opting out, for one release

Building with `-Duse_openssl` serves and connects through OpenSSL with the
same settings, held to TLS 1.3. Client certificates (PostgreSQL `sslcert`
and `sslkey`, MySQL `ssl-cert` and `ssl-key`) still need `-Duse_openssl`;
Beryl refuses them with an error that says so. The flag is removed in the
release after this one.

## Vendored Beryl

The vendored copy moves to Beryl 0.2.1 (amberframework/beryl), pinned by
commit and per-file sha256: v0.2.0's TLS 1.3 with per-connection record
buffer reuse, `TLS::Socket#closed?`, and issuer matching by name for
certificates without an authority key identifier.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.17 for new apps. For an existing app, move the Amber,
Grant and asset_pipeline pins in `shard.yml` to the release commits (and, for
MySQL, crimson-knight/crystal-mysql), then run
`minecart update amber grant asset_pipeline`. No code or `config/` change is
needed: an app that served HTTPS or sent mail over TLS on beta.15 does so on
Beryl after the pin change alone.

Check before upgrading:

- Every peer must speak TLS 1.3: clients of an app that serves HTTPS itself,
  the mail server, and the database (PostgreSQL `ssl_min_protocol_version =
  'TLSv1.3'`).
- An app that uses client certificates for its database builds with
  `-Duse_openssl` for this release.
