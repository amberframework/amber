# Request and response schemas

Amber V2 schemas are executable controller contracts. One declaration controls request parsing, validation, typed values, response validation, content negotiation, and OpenAPI output. A declared controller schema runs automatically before the action; it cannot become documentation that the application forgets to enforce.

The V1 params validator remains available, but it is deprecated. Amber plans to keep it throughout the initial V2 compatibility window and remove it no earlier than a later minor release such as 2.5. The exact removal release will be announced separately. You can therefore upgrade the framework first and migrate one action at a time.

## Build a complete JSON endpoint

This example creates a pet through `POST /pets`. Every code sample names the file where it belongs.

### 1. Define the contracts

Create `src/schemas/pet_schemas.cr`:

```crystal
class CreatePetSchema < Amber::Schema::Definition
  content_type "application/json"
  additional_properties false

  field :name, String, required: true, min_length: 1, max_length: 80
  field :species, String, required: true, enum: ["cat", "dog", "other"]
  field :age, Int32, min: 0, max: 50
  field :request_id, String,
    required: true,
    source: Amber::Schema::ParamSource::Header,
    source_name: "X-Request-ID"
end

class PetResponseSchema < Amber::Schema::Definition
  content_type "application/json"
  additional_properties false

  field :id, Int64, required: true
  field :name, String, required: true
  field :species, String, required: true
  field :age, Int32
end
```

`additional_properties false` makes the object a closed contract. An undeclared body or response field then produces a validation error. Omit that line when an existing API must continue accepting and carrying additional fields.

### 2. Bind the contracts to the action

Create or update `src/controllers/pets_controller.cr`:

```crystal
require "../schemas/pet_schemas"

class PetsController < ApplicationController
  schema :create, CreatePetSchema
  response_schema :create,
    PetResponseSchema,
    status: 201,
    description: "Pet created"

  def create
    input = validated_as(CreatePetSchema)
    pet = Pet.create!(
      name: input.name.not_nil!,
      species: input.species.not_nil!,
      age: input.age
    )

    payload = {
      "id"      => JSON::Any.new(pet.id),
      "name"    => JSON::Any.new(pet.name),
      "species" => JSON::Any.new(pet.species),
    }
    payload["age"] = JSON::Any.new(pet.age.not_nil!) if pet.age

    respond_with(payload, status: 201)
  end
end
```

Amber parses and validates the request before `create` runs. `validated_as` returns the request-local schema instance and its typed getters. `validated_params` is also available when a `Hash(String, JSON::Any)` is more convenient.

`respond_with` checks the response object and HTTP status before writing any bytes. A response that violates `PetResponseSchema` becomes an HTTP 500 contract error instead of silently returning an undocumented shape.

### 3. Add the route

Add this route inside the router block in `config/routes.cr`:

```crystal
post "/pets", PetsController, :create
```

### 4. Exercise the contract

Run this from the application root while `amber watch` is running:

```bash
curl --fail-with-body \
  --request POST \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --header 'X-Request-ID: guide-1' \
  --data '{"name":"Mochi","species":"cat","age":3}' \
  http://127.0.0.1:3000/pets
```

The automatic failure statuses are:

| Status | Meaning |
|---|---|
| `400` | The body is malformed JSON, CBOR, or COSE. |
| `406` | The requested response media type is not declared by the response schema. |
| `415` | The request `Content-Type` is not declared by the request schema. |
| `422` | The document parsed, but its values do not satisfy the schema. |
| `500` | Application code produced a response shape or status outside its declared contract. |
| `503` | A COSE request arrived before a key provider was configured. |

Actions without a declared schema retain their existing params behavior.

## Field types and constraints

The built-in field types are `String`, `Int32`, `Int64`, `Float32`, `Float64`, `Bool`, `Time`, `UUID`, typed `Array(T)`, and `Hash(String, T)`. An unknown type is rejected unless the application registers an explicit coercion for it.

```crystal
field :email, String, required: true, format: "email"
field :role, String, default: "member", enum: ["member", "admin"]
field :score, Float64, min: 0.0, max: 1.0
field :nickname, String, min_length: 2, max_length: 30
field :slug, String, pattern: "^[a-z0-9-]+$"
field :tags, Array(String)
field :scores, Hash(String, Int32)
```

Validation fails when any member of a typed collection cannot be coerced. Amber never drops an invalid member and then reports the shortened collection as valid.

Supported formats include `email`, `url` or `uri`, `uuid`, `iso8601` or `datetime`, `date`, `time`, `ipv4`, `ipv6`, and `hostname`.

## Body, path, query, and header values

The default source is the request body. Set `source` when a value belongs elsewhere. Use `source_name` when the wire name is not a valid or idiomatic Crystal method name.

Put this schema in `src/schemas/show_pet_schema.cr`:

```crystal
class ShowPetSchema < Amber::Schema::Definition
  field :id, Int64,
    required: true,
    source: Amber::Schema::ParamSource::Path

  field :include_visits, Bool,
    default: false,
    source: Amber::Schema::ParamSource::Query,
    source_name: "include_visits"

  field :request_id, String,
    source: Amber::Schema::ParamSource::Header,
    source_name: "X-Request-ID"
end
```

Then bind it in `src/controllers/pets_controller.cr` and declare the matching path in `config/routes.cr`:

```crystal
# src/controllers/pets_controller.cr
schema :show, ShowPetSchema

def show
  input = validated_as(ShowPetSchema)
  pet = Pet.find!(input.id.not_nil!)
  # Render the pet...
end
```

```crystal
# config/routes.cr
get "/pets/:id", PetsController, :show
```

## Conditional and nested contracts

`when_field` and `when_present` make fields required only when their condition applies:

```crystal
class AccountSchema < Amber::Schema::Definition
  field :kind, String, required: true, enum: ["person", "business"]

  when_field :kind, "person" do
    field :first_name, String, required: true
    field :last_name, String, required: true
  end

  when_field :kind, "business" do
    field :company_name, String, required: true
    field :tax_id, String, required: true
  end
end
```

Use `requires_together :latitude, :longitude` when all named fields must appear together. Use `requires_one_of :email, :phone` when exactly one must appear. Use `nested :address, AddressSchema` to validate an object with another schema; nested error paths are prefixed, such as `address.city`.

## JSON, CBOR, and encrypted COSE

Declare every request and response representation the action actually supports:

```crystal
content_type "application/json", "application/cbor", "application/cose"
```

- `application/json` uses the same object contract as ordinary Amber JSON APIs.
- `application/cbor` carries the JSON-compatible contract as deterministic CBOR.
- `application/cose` carries that CBOR document in a tagged COSE Encrypt0 envelope using ChaCha20-Poly1305.

CBOR decoding is bounded to a 1 MiB document, 32 levels of nesting, and 16,384 collection items. It rejects indefinite lengths, duplicate map keys, invalid UTF-8, trailing bytes, byte strings where a JSON-compatible value is required, and non-finite numbers.

COSE authenticates both inbound and outbound messages. Amber generates a fresh 96-bit nonce for every response, selects keys by COSE key ID, and supports a grace key during rotation. There is no built-in development key.

Generate a 32-byte key from the application root:

```bash
openssl rand -base64 32
```

Store the result in the deployment secret manager as `AMBER_WIRE_KEY`, and store a non-empty key ID such as `2026-08` as `AMBER_WIRE_KEY_ID`. Do not commit either value.

Create `config/wire_format.cr`:

```crystal
Amber::Schema::COSE.configure(
  Amber::Schema::COSE::KeyProvider.from_env!
)
```

Require it after `require "amber"` and before the controller glob in `config/application.cr`:

```crystal
require "amber"
require "./wire_format"
require "../src/controllers/application_controller"
require "../src/controllers/**"
require "./routes"
```

Clients send COSE Encrypt0 with algorithm `24` and receive the same interoperable envelope. The `X-Amber-Wire-Format` response header describes Amber's selected profile; it is informational and is not a substitute for verifying the authenticated COSE message.

## Generate OpenAPI from the same contract

The ordinary Amber router records route metadata. `Amber::Schema::OpenAPI.generate` combines it with the registered request and response schemas, including path/query/header parameters, body fields, supported media types, response status, constraints, and automatic error responses.

Create `src/controllers/open_api_controller.cr`:

```crystal
class OpenAPIController < ApplicationController
  def show
    response.content_type = "application/json"
    Amber::Schema::OpenAPI.generate(
      title: "Pet Tracker API",
      version: "2.0.0",
      description: "The executable contract for the Pet Tracker API",
      server_url: ENV["PUBLIC_URL"]? || "http://127.0.0.1:3000"
    )
  end
end
```

Add the endpoint in `config/routes.cr`:

```crystal
get "/openapi.json", OpenAPIController, :show
```

Request-body components contain only body fields. Path, query, header, and cookie fields are emitted as OpenAPI parameters, so the generated document does not incorrectly require a header field inside the JSON body.

## Migrate the deprecated validator gradually

Existing V1-style code continues to compile and run in Amber V2:

```crystal
validation = params.validation do
  required(:email) { |value| value.email? }
end
```

The compiler emits a deprecation warning because new code should use a controller schema. This warning is not a removal in V2.0. A safe application migration is:

1. Upgrade Amber and verify the existing application without rewriting validation.
2. Define a schema for one action.
3. Bind it with `schema :action, SchemaClass`.
4. Replace reads with `validated_as(SchemaClass)` or `validated_params`.
5. Add a response schema for API actions.
6. Repeat per action.

After a schema succeeds, `params` prioritizes its normalized values and falls back to the existing raw params wrapper for undeclared keys. This is the compatibility bridge that lets a controller move incrementally instead of requiring an application-wide conversion.
