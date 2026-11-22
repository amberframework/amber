# Amber 2.0.0-beta.13

Amber 2.0.0-beta.13 is a security release. It holds the `charset` a client
names on a form to the WHATWG Encoding Standard.

## Security: a form's `charset` is held to the WHATWG Encoding Standard (#1460)

Through beta.12 the `charset` a client declared on a URL-encoded form went
straight to iconv, so on Linux a request could open any converter glibc ships
by naming it. From beta.13 Amber accepts only the labels of the
[WHATWG Encoding Standard](https://encoding.spec.whatwg.org/#names-and-labels),
in any letter case, and each label opens the one decoder Amber maps it to.

A form whose `charset` is anything else is answered
`415 Unsupported Media Type` before its body is read. That covers `UTF-7`,
`ISO-2022-CN-EXT`, an empty or oversized name, and the standard's
`replacement`, `x-user-defined`, `windows-1255` and `windows-1258` encodings
(glibc decodes the last two by holding back the final letter). The request
raises `Amber::Exceptions::UnsupportedCharset`, a `BadRequest`, and a schema
parse reports it as `unsupported_media_type`. A UTF-8 label parses the form
directly, with no converter. Multipart and JSON bodies never took an encoding
name from the request and behave as before.

`CHANGELOG.md` has the complete list.

## Upgrading

Every app on beta.12 or earlier should upgrade. Use Amber CLI 2.0.13 for new
apps. For an existing app, pin the release commit in `shard.yml`, run
`minecart update amber`, and run `amber setup:agent`. Amber CLI 2.0.13 also
moves new apps to Grant `v0.25.0`, whose `BigDecimal` support is opt-in: an
app with `BigDecimal` columns adds `require "grant/big_decimal"` above
`require "grant"`. asset_pipeline stays at `v0.38.0`.
