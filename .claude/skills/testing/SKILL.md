---
name: amber-testing
description: Amber V2 testing framework — ContextBuilder for request simulation, controller testing, WebSocket test helpers, assertions
user-invocable: false
---

# Testing Framework

Amber V2 includes a built-in testing framework for controller testing, request simulation, and WebSocket verification. It builds fake HTTP contexts without starting a real server, routes requests through the Amber pipeline, and provides assertion helpers for response inspection.

## Entry Point

`src/amber/testing.cr` requires `src/amber/testing/testing.cr`, which loads all components:

```crystal
require "amber/testing"
```

## ContextBuilder

Builds `HTTP::Server::Context` objects for testing without a running server. Uses a builder pattern where every setter returns `self` for chaining.

```crystal
context = Amber::Testing::ContextBuilder.new
  .method("POST")
  .path("/users")
  .header("Content-Type", "application/json")
  .json_body({name: "Alice", age: 30})
  .build
```

### Builder Methods

| Method | Signature | Purpose |
|---|---|---|
| `method` | `(m : String) : self` | Set HTTP method (auto-uppercased) |
| `path` | `(p : String) : self` | Set request path |
| `header` | `(key : String, value : String) : self` | Add a single header |
| `body` | `(b : String) : self` | Set raw request body |
| `json_body` | `(data) : self` | Set body as JSON, auto-sets `Content-Type: application/json` |
| `query_param` | `(key : String, value : String) : self` | Add a single query parameter |
| `params` | `(p : Hash(String, String)) : self` | Add multiple query parameters from a hash |
| `build` | `: HTTP::Server::Context` | Build the context (response backed by `IO::Memory`) |
| `build_with_io` | `: {HTTP::Server::Context, IO::Memory}` | Build context and return the response IO for reading raw bytes |

### Defaults

When no methods are called, `ContextBuilder` produces a `GET /` request with empty headers and empty body.

### Query Parameter Handling

Query parameters are appended to the path at build time. If the path already contains a `?`, parameters are joined with `&`:

```crystal
context = Amber::Testing::ContextBuilder.new
  .path("/search?q=crystal")
  .query_param("page", "2")
  .build

context.request.query_params["q"]    # => "crystal"
context.request.query_params["page"] # => "2"
```

### Reading Raw Response Bytes

Use `build_with_io` when you need to read the response body after processing:

```crystal
context, io = Amber::Testing::ContextBuilder.new
  .method("GET")
  .path("/test")
  .build_with_io

# Process the context through a handler...
context.response.status_code = 200
context.response.print("Hello, Test!")
context.response.close

io.rewind
client_response = HTTP::Client::Response.from_io(io, decompress: false)
client_response.body  # => "Hello, Test!"
```

Source: `src/amber/testing/context_builder.cr`

## Testing Controller Actions

### Direct Controller Testing with ControllerHelpers

Include `Amber::Testing::ControllerHelpers` to build controller instances and assert on their responses directly. This tests controllers in isolation without routing through the pipeline.

```crystal
require "amber/testing"

class ArticlesController < Amber::Controller::Base
  def index
    "Articles List"
  end

  def create
    response.status_code = 201
    response.headers["Content-Type"] = "application/json"
    %({"id": 1, "created": true})
  end

  def redirect_example
    redirect_to "/login"
  end
end

class ArticlesTestRunner
  include Amber::Testing::ControllerHelpers

  def test_index
    controller = build_controller(ArticlesController, :index)
    controller.index  # => "Articles List"
  end

  def test_create
    controller = build_controller(ArticlesController, :create, method: "POST")
    controller.create
    assert_controller_response(controller, 201)
    assert_controller_content_type(controller, "application/json")
  end

  def test_redirect
    controller = build_controller(ArticlesController, :redirect_example)
    controller.redirect_example
    assert_controller_redirect_to(controller, "/login")
  end
end
```

### The `build_controller` Macro

```crystal
build_controller(controller_class, action = :index, method = "GET", path = "/")
```

This is a macro (not a method) because the controller class must be known at compile time. It creates a `ContextBuilder`, builds the context, and instantiates the controller.

### The `build_test_context` Method

For more control over the context without instantiating a controller:

```crystal
context = build_test_context(
  method: "POST",
  path: "/users",
  headers: HTTP::Headers{"Accept" => "application/json"},
  params: {"name" => "Alice", "role" => "admin"}
)
```

### Controller Assertion Methods

| Method | Purpose |
|---|---|
| `assert_controller_response(controller, status)` | Status code matches |
| `assert_controller_redirect_to(controller, path)` | Response is a redirect (3xx) to the given path |
| `assert_controller_content_type(controller, type)` | Content-Type header contains the given string |

Source: `src/amber/testing/controller_helpers.cr`

## Request Simulation with RequestHelpers

Include `Amber::Testing::RequestHelpers` to send requests through the full Amber pipeline (routes, pipes, controller). This is integration-level testing.

```crystal
require "amber/testing"

# Define routes before tests
Amber::Server.router.draw :web do
  get "/articles", ArticlesController, :index
  get "/articles/:id", ArticlesController, :show
  post "/articles", ArticlesController, :create
  put "/articles/:id", ArticlesController, :update
  delete "/articles/:id", ArticlesController, :destroy
end

Amber::Server.handler.build(:web) { }

module ArticlesSpec
  extend Amber::Testing::RequestHelpers

  describe "ArticlesController" do
    it "lists articles" do
      response = ArticlesSpec.get("/articles")
      response.status_code.should eq(200)
      response.body.should contain("Articles")
    end

    it "creates an article with JSON" do
      response = ArticlesSpec.post_json("/articles", {title: "New Article"})
      response.status_code.should eq(200)
    end

    it "returns 404 for unknown routes" do
      response = ArticlesSpec.get("/nonexistent")
      response.status_code.should eq(404)
    end
  end
end
```

### Request Methods

| Method | Signature | Notes |
|---|---|---|
| `get` | `(path, headers?) : TestResponse` | GET request |
| `post` | `(path, body?, headers?) : TestResponse` | POST with optional raw body |
| `put` | `(path, body?, headers?) : TestResponse` | PUT with optional raw body |
| `patch` | `(path, body?, headers?) : TestResponse` | PATCH with optional raw body |
| `delete` | `(path, headers?) : TestResponse` | DELETE request |
| `head` | `(path, headers?) : TestResponse` | HEAD request |
| `post_json` | `(path, body) : TestResponse` | POST with JSON body, sets `Content-Type` and `Accept` to `application/json` |
| `put_json` | `(path, body) : TestResponse` | PUT with JSON body |
| `patch_json` | `(path, body) : TestResponse` | PATCH with JSON body |

### How Pipeline Routing Works

Each request helper internally:

1. Builds a context via `ContextBuilder`
2. Gets the pipeline handler from `Amber::Server.handler`
3. Calls `prepare_pipelines` and `call(context)` on it
4. Closes the response, rewinds the IO
5. Parses the raw bytes into an `HTTP::Client::Response`
6. Wraps it in a `TestResponse`

This means routes and pipes must be configured before tests run.

Source: `src/amber/testing/request_helpers.cr`

## TestResponse

Wraps the result of a request made through `RequestHelpers`. Provides convenience methods for status checking, JSON parsing, and header inspection.

```crystal
response = ArticlesSpec.get("/articles/1")

# Status inspection
response.status_code         # => 200
response.successful?         # => true  (2xx)
response.redirect?           # => false (3xx)
response.client_error?       # => false (4xx)
response.server_error?       # => false (5xx)

# Body access
response.body                # => raw body string
response.json                # => JSON::Any (raises on invalid JSON)

# Header inspection
response.content_type        # => "application/json" or nil
response.redirect_url        # => Location header value or nil
response.headers["X-Custom"] # => header value
```

### Constructor

```crystal
TestResponse.new(status_code : Int32, body : String, headers : HTTP::Headers)
TestResponse.from_client_response(response : HTTP::Client::Response) : TestResponse
```

Source: `src/amber/testing/test_response.cr`

## Assertions

Domain-specific assertion helpers that complement Crystal's built-in `should` matchers. Include `Amber::Testing::Assertions` alongside `RequestHelpers` for the full assertion vocabulary.

```crystal
module MyAppSpec
  extend Amber::Testing::RequestHelpers
  extend Amber::Testing::Assertions

  describe "API" do
    it "returns JSON success" do
      response = MyAppSpec.get("/api/status")
      MyAppSpec.assert_response_success(response)
      MyAppSpec.assert_json_content_type(response)
      json = MyAppSpec.assert_json_body(response)
      json["status"].as_s.should eq("ok")
    end

    it "redirects unauthenticated users" do
      response = MyAppSpec.get("/dashboard")
      MyAppSpec.assert_redirect_to(response, "/login")
    end
  end
end
```

### Available Assertions

| Method | Checks |
|---|---|
| `assert_response_status(response, status)` | Exact status code match |
| `assert_response_success(response)` | Status is 2xx |
| `assert_response_redirect(response)` | Status is 3xx |
| `assert_redirect_to(response, path)` | Status is 3xx and `Location` header matches path |
| `assert_response_client_error(response)` | Status is 4xx |
| `assert_response_not_found(response)` | Status is 404 |
| `assert_response_server_error(response)` | Status is 5xx |
| `assert_content_type(response, type)` | Content-Type header contains the given string |
| `assert_json_content_type(response)` | Content-Type contains `application/json` |
| `assert_html_content_type(response)` | Content-Type contains `text/html` |
| `assert_body_contains(response, text)` | Body contains the given string |
| `assert_json_body(response) : JSON::Any` | Body is valid JSON; returns parsed result |
| `assert_header(response, key, value)` | Specific header has exact value |

Source: `src/amber/testing/assertions.cr`

## WebSocket Test Helpers

Test WebSocket channels by creating real socket connections on ephemeral ports.

```crystal
require "amber/testing"

module ChatSpec
  extend Amber::Testing::WebSocketHelpers

  describe "ChatChannel" do
    it "connects and sends messages" do
      test_socket = ChatSpec.create_test_socket("/chat")

      test_socket.send("hello")
      test_socket.list_of_sent_messages.size.should eq(1)
      test_socket.list_of_sent_messages.first.should eq("hello")

      test_socket.close
    end

    it "sends structured JSON messages" do
      test_socket = ChatSpec.create_test_socket("/chat")

      test_socket.send_json("join", "room:lobby", {"user" => "Alice"})
      message = JSON.parse(test_socket.list_of_sent_messages.first)
      message["event"].as_s.should eq("join")
      message["topic"].as_s.should eq("room:lobby")

      test_socket.close
    end

    it "prevents sending after close" do
      test_socket = ChatSpec.create_test_socket("/ws")
      test_socket.close
      test_socket.is_closed?.should be_true

      expect_raises(Exception, "Cannot send on a closed socket") do
        test_socket.send("should fail")
      end
    end
  end
end
```

### WebSocketHelpers Module

| Method | Returns | Purpose |
|---|---|---|
| `create_test_socket(path)` | `TestWebSocket` | Create a connected test socket on the given path |

### TestWebSocket Class

| Method/Getter | Type | Purpose |
|---|---|---|
| `send(message)` | | Send a raw string message |
| `send_json(event, topic, payload)` | | Send structured JSON with event, topic, and payload |
| `receive` | `String?` | Most recently received message, or nil |
| `close` | | Close the socket and shut down the test server |
| `list_of_received_messages` | `Array(String)` | All messages received from server |
| `list_of_sent_messages` | `Array(String)` | All messages sent by the test |
| `is_closed?` | `Bool` | Whether the socket has been closed |

### Internal TestClientSocket

`TestWebSocket` starts a minimal HTTP server using `Amber::WebSockets::Server.create_endpoint` with an internal `TestClientSocket` struct. For testing your own channel types, use `WebSocketHelpers` with your actual socket structs.

Source: `src/amber/testing/websocket_helpers.cr`

## Flash and Session Testing

### Session Testing

Controllers expose session access through the context. Use `build_controller` or `ContextBuilder` to set up session values:

```crystal
controller = build_controller(MyController, :index)
controller.session["user_id"] = "42"
controller.session["user_id"].should eq("42")
controller.session.id.not_nil!.size.should eq(36)
```

### Flash Testing

The `Flash::FlashStore` is session-backed. Test it directly:

```crystal
# Create a flash store with initial values
flash_store = Amber::Router::Flash::FlashStore.new
flash_store["notice"] = "Item created"
flash_store["notice"].should eq("Item created")

# Values are marked as read after fetch
flash_store.fetch("notice")
new_store = Amber::Router::Flash::FlashStore.from_session(flash_store.to_session)
new_store.has_key?("notice").should be_false  # consumed after read

# Use .now for current-request-only values
flash_store.now("error", "Something went wrong")

# Use .keep to persist after reading
flash_store.keep("notice")
```

Flash supports both String and Symbol keys. Writing with `:key` and reading with `"key"` works interchangeably.

## Testing with the Schema API

Schema validation is testable in isolation by constructing a schema with raw data and calling `validate`:

```crystal
class CreateUserSchema < Amber::Schema::Definition
  field :email, String, required: true, format: "email"
  field :name, String, required: true, min_length: 2
  field :age, Int32, min: 18, max: 120
end

describe CreateUserSchema do
  it "validates correct data" do
    data = {
      "email" => JSON::Any.new("alice@example.com"),
      "name"  => JSON::Any.new("Alice"),
      "age"   => JSON::Any.new(30),
    }

    schema = CreateUserSchema.new(data)
    result = schema.validate

    result.success?.should be_true
    schema.email.should eq("alice@example.com")
    schema.name.should eq("Alice")
    schema.age.should eq(30)
  end

  it "rejects missing required fields" do
    data = {"age" => JSON::Any.new(25)}

    schema = CreateUserSchema.new(data)
    result = schema.validate

    result.failure?.should be_true
    result.errors.any? { |e| e.field == "email" }.should be_true
    result.errors.any? { |e| e.field == "name" }.should be_true
  end

  it "rejects invalid formats" do
    data = {
      "email" => JSON::Any.new("not-an-email"),
      "name"  => JSON::Any.new("Alice"),
    }

    schema = CreateUserSchema.new(data)
    result = schema.validate

    result.failure?.should be_true
    result.errors.any? { |e|
      e.is_a?(Amber::Schema::InvalidFormatError) && e.field == "email"
    }.should be_true
  end

  it "rejects out-of-range values" do
    data = {
      "email" => JSON::Any.new("alice@example.com"),
      "name"  => JSON::Any.new("Alice"),
      "age"   => JSON::Any.new(15),
    }

    schema = CreateUserSchema.new(data)
    result = schema.validate

    result.failure?.should be_true
    result.errors.any? { |e|
      e.is_a?(Amber::Schema::RangeError) && e.field == "age"
    }.should be_true
  end

  it "provides grouped error details" do
    data = {
      "email" => JSON::Any.new("invalid"),
      "name"  => JSON::Any.new("X"),
      "age"   => JSON::Any.new(200),
    }

    schema = CreateUserSchema.new(data)
    result = schema.validate

    errors_by_field = result.errors_by_field
    errors_by_field.has_key?("email").should be_true
    errors_by_field.has_key?("name").should be_true
    errors_by_field.has_key?("age").should be_true
  end
end
```

### Testing with Typed Results

```crystal
it "returns typed Success" do
  data = {"name" => JSON::Any.new("Test")}
  schema = SimpleSchema.new(data)
  result = schema.validate_typed

  result.should be_a(Amber::Schema::Success(Hash(String, JSON::Any)))
  result.success?.should be_true
end

it "returns typed Failure" do
  data = {} of String => JSON::Any
  schema = SimpleSchema.new(data)
  result = schema.validate_typed

  result.should be_a(Amber::Schema::Failure(Hash(String, JSON::Any)))
  result.failure?.should be_true
end
```

### Testing Controller + Schema Integration

Controllers that include schema integration expose `request_data`, `validation_result`, `validated_params`, and `validation_failed?`:

```crystal
it "provides schema validation methods" do
  request = HTTP::Request.new("POST", "/test")
  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)

  controller = MyController.new(context)

  controller.responds_to?(:request_data).should be_true
  controller.responds_to?(:validation_result).should be_true
  controller.responds_to?(:validated_params).should be_true
  controller.responds_to?(:validation_failed?).should be_true
end

it "merges data from query params and JSON body" do
  request = HTTP::Request.new("POST", "/test?query=value")
  request.headers["Content-Type"] = "application/json"
  request.body = IO::Memory.new("{\"body\":\"data\"}")

  response = HTTP::Server::Response.new(IO::Memory.new)
  context = HTTP::Server::Context.new(request, response)

  controller = MyController.new(context)
  merged = controller.merge_request_data

  merged["query"]?.should_not be_nil
  merged["body"]?.should_not be_nil
end
```

## Test Organization Patterns

### Spec File Structure

Amber specs follow Crystal's standard `describe`/`context`/`it` blocks:

```crystal
require "../spec_helper"
require "../../src/amber/testing"

describe "ArticlesController" do
  describe "#index" do
    it "returns a list of articles" do
      # test body
    end

    context "when unauthenticated" do
      it "redirects to login" do
        # test body
      end
    end
  end

  describe "#create" do
    context "with valid params" do
      it "creates the article" do
        # test body
      end
    end

    context "with invalid params" do
      it "returns validation errors" do
        # test body
      end
    end
  end
end
```

### Using `extend` for Module Helpers

Since `RequestHelpers` and `Assertions` are modules with instance methods, use `extend` to make them available as class-level methods callable from within `describe` blocks:

```crystal
module ArticlesSpec
  extend Amber::Testing::RequestHelpers
  extend Amber::Testing::Assertions

  describe "Articles API" do
    it "returns success" do
      response = ArticlesSpec.get("/articles")
      ArticlesSpec.assert_response_success(response)
    end
  end
end
```

### Spec Helper Setup

The standard `spec_helper.cr` sets the environment, encryption key, and paths:

```crystal
ENV["AMBER_ENV"] = "test"
ENV[Amber::Support::ENCRYPT_ENV] = "your_encryption_key_here"

Amber.path = "./spec/support/config"
Amber.env = ENV["AMBER_ENV"]

require "http"
require "spec"
require "../src/amber"
require "./support/fixtures"
require "./support/helpers"
```

### Route Setup for Integration Tests

Routes must be drawn and the handler built before `RequestHelpers` tests run. Place this at the top level of the spec file:

```crystal
Amber::Server.router.draw :web do
  get "/articles", ArticlesController, :index
  post "/articles", ArticlesController, :create
end

Amber::Server.handler.build(:web) { }
```

## Running Tests

```bash
# Run the full test and lint suite (recommended)
./bin/amber_spec

# Individual commands:
./bin/ameba                    # Linter
crystal tool format --check    # Formatting check
crystal spec                   # Full spec suite

# Run a single spec file
crystal spec spec/amber/testing/context_builder_spec.cr

# Run a specific module's specs
crystal spec spec/amber/testing/

# Run specs matching a pattern
crystal spec --tag focus
```

## Key Source Files

| File | Contains |
|---|---|
| `src/amber/testing.cr` | Entry point, requires `testing/testing.cr` |
| `src/amber/testing/testing.cr` | Loads all testing components |
| `src/amber/testing/context_builder.cr` | `ContextBuilder` class with builder pattern |
| `src/amber/testing/controller_helpers.cr` | `ControllerHelpers` module with `build_controller` macro |
| `src/amber/testing/request_helpers.cr` | `RequestHelpers` module with HTTP verb methods |
| `src/amber/testing/test_response.cr` | `TestResponse` class wrapping response data |
| `src/amber/testing/assertions.cr` | `Assertions` module with domain-specific assertions |
| `src/amber/testing/websocket_helpers.cr` | `WebSocketHelpers` module and `TestWebSocket` class |
| `spec/amber/testing/context_builder_spec.cr` | ContextBuilder specs |
| `spec/amber/testing/controller_helpers_spec.cr` | ControllerHelpers specs |
| `spec/amber/testing/request_helpers_spec.cr` | RequestHelpers specs |
| `spec/amber/testing/test_response_spec.cr` | TestResponse specs |
| `spec/amber/testing/assertions_spec.cr` | Assertions specs |
| `spec/amber/testing/websocket_helpers_spec.cr` | WebSocketHelpers specs |
