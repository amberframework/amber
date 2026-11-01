# Zero-link evidence: Amber V2 without libxml2

This folder shows what a static build of this sample app links before and
after Amber 2.0.0-beta.6, and that the after build still accepts XML request
bodies through Mica.

## The app

`examples/zero_link_app` was generated with `amber new zero_link_app -d pg`
(Amber CLI, amber_cli `ad24f1c`). It adds one Grant model (`Subscriber`), one
schema (`CreateSubscriberSchema`, JSON and XML), one API action
(`POST /api/subscribers`), a migration, and
`config/initializers/request_body_parsers.cr`, which registers
`Mica::XML::Fields` for `application/xml` and `text/xml`.

| Variant | Amber | XML parser | Manifest and lock |
|---|---|---|---|
| before | 2.0.0-beta.5 | built in, stdlib `XML` (libxml2) | `baseline/shard.yml`, `baseline/shard.lock` |
| after | v2-dev `b9d246ba` (#1414 merged) | Mica (`amberframework/mica`), opt-in | `../shard.yml`, `../shard.lock` |

Both locks record a `git-tree` checksum for every dependency, and every
install runs `shards-alpha install --frozen`.

## How it was built

`build_static.sh 2` builds each variant twice in
`crystallang/crystal:1.22.1-alpine@sha256:9beda8a9d4a3659c29d185cc18f3fb9b382421bb6a4a59b8f266a6fb4ccc9f16`
(Crystal 1.22.1, musl, linux/arm64 under Docker on an Apple Silicon Mac), with `--static --release --no-debug`, an empty
compiler cache per build, and a linker map (`-Wl,-Map`).
`build_in_container.sh` and `inspect_in_container.sh` run inside the image.
`smoke_static.sh` runs the after binary in a bare Alpine 3.22.2 container
(no libxml2 installed) against PostgreSQL 17.6 and sends it JSON, XML and
hostile XML.

## Results

| | before (beta.5) | after (#1414 + Mica) |
|---|---|---|
| libxml2 objects linked | 108 | 0 |
| liblzma objects linked | 68 | 0 |
| zlib objects linked | 15 | 11 |
| static archives used | 12 | 10 |
| defined `xml*` / `lzma_*` / zlib symbols | 2,420 / 109 / 46 | 0 / 0 / 46 |
| `-l` flags | adds `-lxml2 -llzma` | neither |
| binary size | 29,600,248 bytes | 26,103,720 bytes (11.8% smaller) |
| binary size after `strip` | 11,169,352 bytes | 10,381,728 bytes (7.1% smaller) |
| dynamic libraries needed (`readelf -d`) | none (static PIE) | none (static PIE) |
| clean release build, 2 runs | 109.0 s, 119.0 s | 93.0 s, 81.0 s |

Both binaries are static: `readelf -d` lists no NEEDED entries and there is
no program interpreter. zlib stays linked because Grant
(`grant/encryption/compression.cr`) and asset_pipeline
(`asset_pipeline/static_assets.cr`) use the standard library's `Compress`;
Amber itself does not. The remaining archives are libc, libcrypto, libssl,
libgc, libgmp, libpcre2-8, libyaml, libz and the compiler's libgcc and
libgcc_eh.

Build times are reported, not claimed: in this Docker VM (4 CPUs) the same
beta.5 build ranged from 83 to 133 seconds across five clean builds, so two
runs per variant cannot separate a compile-time change from noise.

The after binary, run in an Alpine image with no libxml2 installed, answered
JSON, `application/xml` and `text/xml` bodies with 201 and wrote 3 rows; an
invalid email with 422; malformed XML with 400 and its position; an external
entity and a billion-laughs body with 400 at the `<!DOCTYPE` (byte 0); and
`application/xhtml+xml` with 415 (`results/after.smoke.txt`).

Measured on 2026-11-01 with Amber `b9d246ba` and Mica `2a4ab10`
(see `../shard.lock`).

## Files in `results/`

- `compile_times.txt`: wall-clock seconds of each build.
- `<variant>.requested_libraries.txt`: the `-l` flags Crystal passed to the linker.
- `<variant>.archive_members.txt`: each static archive the linker took members from, with the member count (from the map's "Archive member included" section).
- `<variant>.binary.txt`: `readelf -d`, the program interpreter, `ldd`, size before and after `strip`, and counts of defined libxml2, liblzma and zlib symbols.
- `<variant>.binary.sha256`: sha256 of each unstripped binary.
- `<variant>.build.log`: the compiler's verbose output, including the link line.
- `after.smoke.txt`: the runtime check.
- `environment.txt`: image, compiler and Docker host.
