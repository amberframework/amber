# Amber 2.0.0-beta.9

Amber 2.0.0-beta.9 adds what an application needs behind a proxy, adds a
security headers pipe, and ships its rules and guides with the framework, so a
language server and a coding assistant know them from the first edit.

## What changed

- **Trusted proxies (#1415).** `server.trusted_proxies` lists the proxies
  allowed to report a client's address and scheme. Amber resolves the client IP
  and decides HTTPS from those proxies only, reads one forwarding header family,
  and validates the setting before it starts serving.
- **UNIX socket listener (#1415).** An application can listen on a UNIX socket.
  The socket is created owner-and-group only, and a bind lock stops two
  processes from taking the same path.
- **`Amber::Pipe::SecurityHeaders` (#1422).** Sends `X-Content-Type-Options`,
  `X-Frame-Options`, `Content-Security-Policy` and `Referrer-Policy`, set through
  a typed `security_headers` section. Plug it into each browser, API and static
  pipeline. See the migration guide.
- **Rule pack for amber-lsp.** `.amber-lsp/packs/amber_v2.yml` checks for Grant
  models, the V2 security headers pipe, ECR views, the JSON perimeter, nil
  narrowing and output through `Log`. Each finding names the fix. Amber CLI 2.0.9
  or newer loads the pack with no setup and prints its guidance at the start of
  an assistant session.
- **API card for amber-lsp.** `amber-lsp lookup` now carries verified notes and
  compiler-error hints for Amber's controller, params, testing and job APIs.
  Public params and validator methods declare concrete return types.
- **Guides for coding assistants.** `minecart install` now copies every guide
  in `docs/guides/` into the application's `.claude/skills/`, with an index skill.

## Upgrade

New applications from Amber CLI 2.0.9 start on this release. For an existing one:

```yaml
dependencies:
  amber:
    github: amberframework/amber
    version: 2.0.0-beta.9
```

Then run `minecart update amber`. If the application runs behind a proxy, list
the proxy in `server.trusted_proxies`, because Amber reads forwarding headers from
listed proxies only. `HTTPS: on` is not read as a scheme signal.

An application that calls `Amber::Validators::Params` directly now sees declared
return types. Code that relied on the earlier inferred unions may need a change
at compile time.

## Release

The tag is `v2.0.0-beta.9`. The GitHub release for the tag states the tagged
commit hash, its tree hash, and the sha256 of the source tarball attached to
the release (`scripts/release_checksums.sh v2.0.0-beta.9` produces all three).
A file cannot carry its own tarball's hash, so they live in the release.
