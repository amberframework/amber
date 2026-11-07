# Amber 2.0.0-beta.10

Amber 2.0.0-beta.10 takes the regex engine out of the request path. A JSON API
built on it links no PCRE2 on stock Crystal, and CI now fails if that changes.

## What changed

- **No PCRE2 in a JSON API.** On stock Crystal 1.22.2, an app with one GET and
  one POST shows no `libpcre2` in `otool -L` or `ldd` and no `pcre2_` symbol in
  `nm`, on macOS and on Linux. `scripts/check_linkage.sh` runs in CI, and its
  control program that uses `Regex` must show PCRE2.
- **Typed route rules (#1442).** Route parameter rules are types, and the router
  uses no regex engine.
- **Fixed patterns became plain code (#1443, #1444).** Amber's internal fixed
  patterns read strings directly, and no pattern uses lookaround.
- **Cookies, form keys, formats and backtraces (#1445).** The `Cookie` header,
  form keys, named schema formats, `String#url?`, backtrace frames and the
  exception page's code coloring use hand-written checks. Each check was compared
  with the pattern it replaced on generated input.
- **A crash removed.** `Validator::Format` with `FormatType::URL` raised
  `Regex::Error` on short crafted input. The new check takes time in proportion
  to the input.
- **One bad cookie no longer fails a request.** Amber leaves that pair out and
  keeps the others.

## Keeping your app free of PCRE2

An app links PCRE2 again when it uses any of these, and it keeps working:

- `pattern:`, `filename_pattern:` or a custom `format:` on a schema field, and
  `validates_pattern` or a custom `validates_format`
- a `Regex` passed to `Pipe::CORS`, `Validator::Pattern` or `Validator::Format`
- Markdown, `strip_tags`, and the other `String` checks such as `email?` and `phone?`
- `request.cookies`; read `cookies` instead
- Grant, whose query code uses `Regex` today
- `Regex` in your own code

## Breaking changes

- A route constraint is a rule, and a `Regex` no longer compiles. Replace
  `{"id" => /\d+/}` with `{"id" => :numeric}`. A rule judges the whole segment,
  so `{"cart" => /\d\d\d/}`, which matched `he110`, becomes
  `NUMERIC.with_length(3)`.
- A `Set-Cookie` header on a request is ignored. Specs that replayed response
  headers as a request must send `Cookie`.
- `Validator::Format::PATTERNS` is removed.
- Backtracer `app_dirs_pattern` is now the prefix list `list_of_app_directories`,
  and `modules_path_pattern` is now the prefix `modules_directory`.
- `Pipe::CORS` copies its origin list when it is built, and `cors.origins` holds
  strings and rule procs. `CORS.new` still accepts `CORS::OriginType`, and now
  also `Array(String)`.
- Phone numbers and the host of a `FormatType::URL` value accept ASCII digits only.
- The schema examples moved to `examples/schema`.

`CHANGELOG.md` has the complete list.

## Upgrading

Use Amber CLI 2.0.10 for new apps. For an existing app, pin the release commit in
`shard.yml`, run `minecart update amber`, and run `amber setup:agent`.
