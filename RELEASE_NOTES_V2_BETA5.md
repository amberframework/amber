# Amber 2.0.0-beta.5

Amber 2.0.0-beta.5 turns the V2 schema API into a contract the framework
actually enforces. A controller declaration now owns request parsing,
validation, typed access, response validation, content negotiation, and
OpenAPI 3.1 output. The release also brings the optimized router and request
path onto the V2 release line.

## Upgrade compatibility comes first

The existing `params.validation` API still compiles and runs. It is deprecated
so new work can use executable controller schemas, but upgrading to beta.5 does
not require rewriting every controller. Applications can update Amber, run
their existing tests, and then migrate one action at a time.

Amber does not plan to remove the deprecated validator before a later V2 minor
such as 2.5. The exact removal release will be announced separately.

## Executable request and response contracts

- `schema :action, SchemaClass` enforces the declared request before the action
  runs.
- `validated_as(SchemaClass)` exposes request-local typed values without
  constructing and validating a second schema object.
- Request fields can come from bodies, paths, query strings, headers, and
  cookies.
- `response_schema` verifies the declared status, content type, and response
  shape before delivery.
- OpenAPI 3.1 operations are generated from the same contracts the application
  executes.
- Server-rendered controllers can override the schema-failure hook to return an
  ECR form with field errors and the correct 400, 415, or 422 status.

## JSON, CBOR, and authenticated COSE

Amber now supports JSON, XML, URL-encoded forms, multipart forms, and bounded
CBOR request parsing. COSE Encrypt0 adds authenticated ChaCha20-Poly1305
encryption in both directions: Amber decrypts and authenticates the inbound
request, applies its schema, and can authenticate and encrypt the response with
a fresh nonce.

The request boundary fails explicitly for malformed documents, unsupported
media, invalid values, unacceptable response formats, invalid declared
responses, and temporarily unavailable encryption configuration.

## Measured performance

The release candidate was tested on a DigitalOcean Basic one-shared-vCPU,
512-MB-class target with a separate load generator, 16 keep-alive connections,
and seven rotating 15-second repetitions per scenario:

| Complete HTTP request path | Median requests/second |
|---|---:|
| Generic JSON decode | 20,728 |
| Schema-validated JSON | 19,488 |
| Schema-validated CBOR | 21,742 |
| Authenticated COSE request and response | 14,443 |

All 7,974,608 retained requests returned HTTP 200. This is a synthetic
in-memory acknowledgement workload without a database, TLS termination,
external services, or HTML rendering. It measures framework, codec, and schema
cost under constrained hardware; it is not a capacity promise for an arbitrary
production application.

See
[`benchmarks/DIGITALOCEAN_SCHEMA_CONTRACT_ROUND27.md`](benchmarks/DIGITALOCEAN_SCHEMA_CONTRACT_ROUND27.md)
for the complete method, ranges, before-and-after comparison, and evidence
paths.

## Start a fresh web application

Amber CLI 2.0.6 is the coordinated generator release for this beta:

```bash
brew install amberframework/amber_cli/amber_cli
amber new pet_tracker --type web
cd pet_tracker
shards install
amber assets check
amber generate scaffold Pet name:string:required species:string:required adopted:bool
amber database migrate
crystal spec
amber watch
```

The generated application uses ECR, Grant, SQLite, Micrate, local front-end
assets, executable HTML form schemas, and Amber `2.0.0-beta.5`.

See the [beta installation guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.5/docs/beta-installation.md),
[migration guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.5/docs/migration-guide.md),
and [schema guide](https://github.com/amberframework/amber/blob/v2.0.0-beta.5/docs/guides/schema-api.md).
