# Amber 2.0.0-beta.7

Amber 2.0.0-beta.7 makes the fixes that AgentC applications carried on a
fork part of Amber itself, so those applications can depend on an official
release again. It also routes `.md` paths to the routes that declare them,
bounds request parameter parsing, and reads credentials from a systemd-style
credentials directory.

## What changed

- **A path ending in an extension reaches the route that declares it
  (#1431).** Beta.6 added `.md` to the response extensions it removes before
  matching, so `/projects/7/insights/overview.md` was matched as
  `/projects/7/insights/overview` and could land on a later `get "/*"`
  catch-all. A route that spells the extension in its own path, such as
  `get "/projects/:project_id/insights/overview.md"` or
  `get "/guides/setup(.md)"`, now answers first. A path that no route
  declares still has its extension removed, so `/users/1.json` matches
  `/users/:id`. A route's request constraint is asked once per request,
  and a constraint that reads `request.params` sees that route's
  parameters.
- **The request body stays readable after Amber parses a form (#1429).** A
  controller behind the CSRF pipe can read `request.body` again; the bytes
  are handed back from the bounded parse. A multipart body is restored up
  to `params.max_multipart_restore_bytes` (8 MiB by default, `0` turns it
  off) when its `Content-Length` is declared and within that limit and
  `params.max_multipart_body_bytes`; any other multipart body stays drained.
- **Upload tempfiles are deleted when the request finishes (#1429).** To
  keep an upload, call `Amber::Router::File#move_to(path)` during the
  action, or `#retain!` to keep the tempfile at `#path` and delete it
  yourself, for example after a background job.
- **Custom config sections load as raw YAML (#1430).** Amber no longer
  deserializes a custom section through every `YAML::Serializable` type, so
  an application whose Grant models have UUID columns compiles with custom
  config again. `AppConfig#custom` reads a section as the requested type or
  returns its registered default; an unregistered key raises
  `Amber::Exceptions::ConfigurationError`.
- **Settings load at first use (#1424).** `require "amber"` no longer reads
  settings, so a section registered in `config/initializers` reads its YAML
  value, and `config/application.cr` can still set `Amber.path` and
  `Amber.env`. Amber colors its own log lines from `logging.colorize` and
  leaves the global `Colorize.enabled` flag alone.
- **Request parameters are bounded (#1419).** Counts, nesting depth, key
  and value sizes, body sizes, array indices and padding, multipart parts,
  uploads and WebSocket messages each have a limit in the new `params:`
  section of `config/environments/<env>.yml` (or `AMBER_PARAMS_<KEY>`). An
  HTTP request beyond a limit is answered with `400 Bad Request`; a
  WebSocket message over `max_websocket_message_bytes` (2 MiB) closes the
  connection with code 1009. The defaults and every limit are listed in
  `CHANGELOG.md`.
- **Credentials directory (#1423).** `Amber::Configuration.register_credentials`
  reads a systemd-style credentials directory, one file per credential, into
  a typed section. The application passes the directory, usually from
  `CREDENTIALS_DIRECTORY`, before settings load:

  ```crystal
  if credentials_directory = ENV["CREDENTIALS_DIRECTORY"]?
    Amber::Configuration.register_credentials(:credentials, AppCredentials, credentials_directory)
  else
    Amber::Configuration.register(:credentials, AppCredentials)
  end
  ```

  `AMBER_{SECTION}_{KEY}` overrides now reach registered custom sections.
- **A GREEN build (#1421):** no compiler warnings. The ecosystem agent
  context now names Micrate, Gemma and Mica (#1417).

## Fork fixes now in Amber

| Fix | Fork commit | Upstream |
|---|---|---|
| Restore the request body after form parsing | `8c71a57c` | #1429 |
| Delete upload tempfiles at request teardown | `0fbd8eba` | #1429 |
| Read custom config as raw YAML | `bc0d62c6` | #1430 |
| Answer 404 before checking a route's constraint when no route matches | `valid_route?` guard | already in Amber (`7224cb57`) |

An application can drop its fork pin and depend on this release.

## Upgrade

Change the version:

```yaml
dependencies:
  amber:
    github: amberframework/amber
    version: 2.0.0-beta.7
```

Then check three things:

- **Uploads you keep.** An action that keeps an uploaded file past the
  request calls `#move_to` or `#retain!`; otherwise the tempfile is gone
  when the response is sent.
- **Large requests.** A form, JSON body or upload larger than the defaults
  (8 MiB form and document bodies, 64 MiB files, 128 MiB multipart bodies)
  needs its limit raised in `params:`.
- **Custom config readers.** Code that called
  `Amber::Configuration.load_custom_from_yaml` reads sections with
  `Amber.settings.custom(:name, Type)` instead.

Beta.6 also stopped sending `Keep-Alive` response headers (`deb16f8e`); a
spec that expects them needs updating.

## Release

The tag is `v2.0.0-beta.7`. The GitHub release for the tag states the tagged
commit hash, its tree hash, and the sha256 of the source tarball attached to
the release (`scripts/release_checksums.sh v2.0.0-beta.7` produces all three).
A file cannot carry its own tarball's hash, so they live in the release.
