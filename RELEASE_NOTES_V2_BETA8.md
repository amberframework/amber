# Amber 2.0.0-beta.8

Amber 2.0.0-beta.8 compiles on every Crystal version its `shard.yml`
declares, starting at 1.20.0, and lets an application choose the cache
policy for the static files it serves.

## What changed

- **Builds on Crystal 1.20 (#1434).** Beta.7 did not compile on Crystal
  1.20.x (`no parameter named 'writable'`), although it declares
  `crystal: ">= 1.20.0"`. Both `IO::Memory` calls now pass the read-only
  flag positionally, and CI runs the full suite on Crystal 1.20.0 next to
  1.22.1 and crystal-alpha.
- **Static files follow the application's cache policy (#1435).**
  `Amber::Pipe::Static` keeps a `Cache-Control` that an earlier handler
  already set. An application with its own fingerprint scheme overrides
  `#cache_control` in a subclass; the hook runs only for a file the pipe
  serves:

  ```crystal
  class AppStatic < Amber::Pipe::Static
    SHORT_FINGERPRINT = /-[0-9a-f]{8}\.[^\/]+$/i

    protected def cache_control(request_path : String) : String
      return IMMUTABLE_CACHE_CONTROL if request_path.matches?(SHORT_FINGERPRINT)
      super
    end
  end
  ```

  Asset headers now go on GET and HEAD responses only.

## Upgrade

```yaml
dependencies:
  amber:
    github: amberframework/amber
    version: 2.0.0-beta.8
```

Then run `minecart update amber`. An application that re-applied its own
`Cache-Control` after `super` in an `apply_asset_headers` override can move
that policy into `#cache_control`.

Amber CLI 2.0.8 generates projects on `2.0.0-beta.7`; change `version:` to
`2.0.0-beta.8` after `amber new`.

## Release

The tag is `v2.0.0-beta.8`. The GitHub release for the tag states the tagged
commit hash, its tree hash, and the sha256 of the source tarball attached to
the release (`scripts/release_checksums.sh v2.0.0-beta.8` produces all three).
A file cannot carry its own tarball's hash, so they live in the release.
