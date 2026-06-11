# Testing Framework

Amber ships with a testing framework built on Crystal's `spec` library. It provides modules for making HTTP requests against your application without starting a real server, building controller instances in isolation, asserting on response properties, and testing WebSocket channels.

## Quick Start

```crystal
require "spec"
require "../src/my_app"

describe "HomeController" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  it "returns the home page" do
    response = get("/")
    assert_response_success(response)
    assert_html_content_type(response)
    assert_body_contains(response, "Welcome")
  end
end
```

## RequestHelpers

Include `Amber::Testing::RequestHelpers` in your spec context to make HTTP requests against the Amber application. Requests are routed through the Amber pipeline programmatically, without starting a real HTTP server.

```crystal
describe "API" do
  include Amber::Testing::RequestHelpers

  it "lists items" do
    response = get("/api/items")
    response.status_code.should eq(200)
  end
end
```

### Available Methods

| Method | Description |
|--------|-------------|
| `get(path, headers?)` | Send a GET request |
| `post(path, body?, headers?)` | Send a POST request |
| `put(path, body?, headers?)` | Send a PUT request |
| `patch(path, body?, headers?)` | Send a PATCH request |
| `delete(path, headers?)` | Send a DELETE request |
| `head(path, headers?)` | Send a HEAD request |
| `post_json(path, body)` | POST with JSON Content-Type and Accept headers |
| `put_json(path, body)` | PUT with JSON Content-Type and Accept headers |
| `patch_json(path, body)` | PATCH with JSON Content-Type and Accept headers |

### Setting Headers

```crystal
headers = HTTP::Headers{"Authorization" => "Bearer token123"}
response = get("/api/protected", headers: headers)
```

### Sending JSON

The `post_json`, `put_json`, and `patch_json` helpers automatically set the `Content-Type` and `Accept` headers to `application/json` and serialize the body with `to_json`:

```crystal
response = post_json("/api/users", {name: "Alice", email: "alice@example.com"})
response.status_code.should eq(201)
```

### Sending Form Data

```crystal
response = post("/users", body: "name=Alice&email=alice%40example.com")
```

## TestResponse

All request helpers return a `TestResponse` object with convenient methods for assertions:

```crystal
response = get("/api/status")

# Status code
response.status_code     # => 200

# Status category checks
response.successful?     # => true  (2xx)
response.redirect?       # => false (3xx)
response.client_error?   # => false (4xx)
response.server_error?   # => false (5xx)

# Body
response.body            # => "{"status":"ok"}"

# JSON parsing (raises JSON::ParseException on invalid JSON)
json = response.json     # => JSON::Any
json["status"].as_s      # => "ok"

# Headers
response.headers         # => HTTP::Headers
response.content_type    # => "application/json"
response.redirect_url    # => String? (Location header)
```

## Assertions

Include `Amber::Testing::Assertions` for domain-specific assertion helpers:

```crystal
describe "API" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  it "returns success" do
    response = get("/api/status")
    assert_response_success(response)
    assert_json_content_type(response)
  end

  it "redirects to login" do
    response = get("/dashboard")
    assert_response_redirect(response)
    assert_redirect_to(response, "/login")
  end

  it "returns 404 for missing resources" do
    response = get("/api/items/999999")
    assert_response_not_found(response)
  end
end
```

### Available Assertions

| Assertion | Description |
|-----------|-------------|
| `assert_response_status(response, code)` | Exact status code match |
| `assert_response_success(response)` | Status is 2xx |
| `assert_response_redirect(response)` | Status is 3xx |
| `assert_redirect_to(response, path)` | Redirect to specific URL |
| `assert_response_client_error(response)` | Status is 4xx |
| `assert_response_not_found(response)` | Status is 404 |
| `assert_response_server_error(response)` | Status is 5xx |
| `assert_content_type(response, type)` | Content-Type contains string |
| `assert_json_content_type(response)` | Content-Type is application/json |
| `assert_html_content_type(response)` | Content-Type is text/html |
| `assert_body_contains(response, text)` | Body contains string |
| `assert_json_body(response)` | Body is valid JSON, returns parsed JSON::Any |
| `assert_header(response, key, value)` | Header has exact value |

## ControllerHelpers

Include `Amber::Testing::ControllerHelpers` to test individual controllers in isolation, without routing through the full pipeline.

### Building Test Contexts

```crystal
include Amber::Testing::ControllerHelpers

# Build a basic context
context = build_test_context(method: "GET", path: "/users")

# Build a context with params
context = build_test_context(
  method: "POST",
  path: "/users",
  headers: HTTP::Headers{"Content-Type" => "application/json"},
  params: {"name" => "Alice"}
)
```

### Building Controllers

The `build_controller` macro creates a controller instance with a test context:

```crystal
include Amber::Testing::ControllerHelpers

describe UsersController do
  it "returns the index page" do
    controller = build_controller(UsersController, :index, "GET", "/users")
    result = controller.index
    result.should contain("Users")
  end
end
```

### Controller Assertions

```crystal
include Amber::Testing::ControllerHelpers

describe UsersController do
  it "responds with 200" do
    controller = build_controller(UsersController, :index, "GET", "/users")
    controller.index
    assert_controller_response(controller, 200)
  end

  it "redirects after create" do
    controller = build_controller(UsersController, :create, "POST", "/users")
    controller.create
    assert_controller_redirect_to(controller, "/users/1")
  end

  it "returns JSON content type" do
    controller = build_controller(UsersController, :index, "GET", "/api/users")
    controller.index
    assert_controller_content_type(controller, "application/json")
  end
end
```

## ContextBuilder

The `ContextBuilder` class provides a fluent interface for constructing `HTTP::Server::Context` objects for testing:

```crystal
context = Amber::Testing::ContextBuilder.new
  .method("POST")
  .path("/users")
  .header("Content-Type", "application/json")
  .json_body({name: "Alice", email: "alice@example.com"})
  .build
```

### Builder Methods

| Method | Description |
|--------|-------------|
| `method(m)` | Set HTTP method (GET, POST, PUT, PATCH, DELETE) |
| `path(p)` | Set request path |
| `header(key, value)` | Add a request header |
| `body(b)` | Set raw string body |
| `json_body(data)` | Set JSON body (auto-sets Content-Type) |
| `query_param(key, value)` | Add a query parameter |
| `params(hash)` | Add multiple query parameters |
| `build` | Build the HTTP::Server::Context |
| `build_with_io` | Build and return {Context, IO::Memory} tuple |

## WebSocketHelpers

Include `Amber::Testing::WebSocketHelpers` for testing WebSocket channels.

```crystal
describe "ChatChannel" do
  include Amber::Testing::WebSocketHelpers

  it "receives messages" do
    test_socket = create_test_socket("/chat")

    test_socket.send_json("join", "chat:lobby")
    test_socket.send_json("message", "chat:lobby", {"text" => "Hello!"})

    test_socket.list_of_received_messages.should_not be_empty
    test_socket.close
  end
end
```

### TestWebSocket

The `TestWebSocket` class wraps a WebSocket connection for use in tests. It tracks sent and received messages.

```crystal
test_socket = create_test_socket("/chat")

# Send a raw message
test_socket.send({"event" => "join", "topic" => "room:1"}.to_json)

# Send a structured JSON message
test_socket.send_json("message", "room:1", {"text" => "Hello"})

# Check received messages
test_socket.list_of_received_messages  # => Array(String)
test_socket.receive                     # => String? (last message)

# Check sent messages
test_socket.list_of_sent_messages      # => Array(String)

# Check connection state
test_socket.is_closed?                 # => Bool

# Clean up
test_socket.close
```

## Complete Test Example

```crystal
require "spec"
require "../src/my_app"

describe "Users API" do
  include Amber::Testing::RequestHelpers
  include Amber::Testing::Assertions

  describe "GET /api/users" do
    it "returns a list of users" do
      response = get("/api/users")
      assert_response_success(response)
      assert_json_content_type(response)

      json = assert_json_body(response)
      json.as_a.should_not be_empty
    end
  end

  describe "POST /api/users" do
    it "creates a user with valid data" do
      response = post_json("/api/users", {
        name:  "Alice",
        email: "alice@example.com",
      })
      assert_response_status(response, 201)
    end

    it "rejects invalid data" do
      response = post_json("/api/users", {name: ""})
      assert_response_client_error(response)
    end
  end

  describe "DELETE /api/users/:id" do
    it "deletes a user" do
      response = delete("/api/users/1")
      assert_response_success(response)
    end
  end
end
```

## Source Files

- `src/amber/testing.cr` -- Module entry point
- `src/amber/testing/request_helpers.cr` -- HTTP request helpers
- `src/amber/testing/controller_helpers.cr` -- Controller isolation helpers
- `src/amber/testing/assertions.cr` -- Domain-specific assertions
- `src/amber/testing/test_response.cr` -- TestResponse wrapper class
- `src/amber/testing/websocket_helpers.cr` -- WebSocket testing helpers
- `src/amber/testing/context_builder.cr` -- Fluent context builder

## Process Manager Testing

Process managers are not controllers. They do not handle HTTP requests, they do not participate in the Amber routing pipeline, and they do not need `RequestHelpers` or a running server. A process manager is a plain Crystal class that receives its dependencies through `initialize`, does its work in `perform`, and exposes results as public properties.

### Testing Pattern

1. Construct the process manager with all dependencies passed as data (arrays, hashes, structs, or model instances).
2. Call `perform`.
3. Assert on the public properties that hold results.

```crystal
require "spec"
require "../src/my_app"

describe Billing::ProcessCustomersWithExpiredPaymentMethods do
  it "retries payment for customers with expired cards" do
    customers = [build_customer(expired: true), build_customer(expired: false)]
    pm = Billing::ProcessCustomersWithExpiredPaymentMethods.new(customers)
    pm.perform
    pm.collection_of_customers_that_were_successfully_retried.size.should be > 0
  end

  it "skips customers with valid payment methods" do
    customers = [build_customer(expired: false)]
    pm = Billing::ProcessCustomersWithExpiredPaymentMethods.new(customers)
    pm.perform
    pm.collection_of_customers_that_were_successfully_retried.size.should eq(0)
  end

  it "records failures for customers that could not be retried" do
    customers = [build_customer(expired: true, will_fail: true)]
    pm = Billing::ProcessCustomersWithExpiredPaymentMethods.new(customers)
    pm.perform
    pm.collection_of_customers_that_failed_retry.size.should eq(1)
  end
end
```

### Why No Server Is Needed

In FSDD, all business logic lives in process managers. Controllers only validate input and delegate to a process manager. This means you can test 100% of your business logic by constructing process managers directly, with no HTTP layer involved.

```crystal
# Controller (thin -- delegates immediately)
class BillingController < Amber::Controller::Base
  def retry_expired
    pm = Billing::ProcessCustomersWithExpiredPaymentMethods.new(Customer.expired)
    pm.perform
    respond_with { json pm.summary.to_json }
  end
end

# The spec tests the PM, not the controller
describe Billing::ProcessCustomersWithExpiredPaymentMethods do
  it "processes the batch" do
    pm = Billing::ProcessCustomersWithExpiredPaymentMethods.new(test_data)
    pm.perform
    pm.summary[:processed].should be > 0
  end
end
```

## Feature Story Test Mapping

FSDD ties every spec file and describe block back to a feature story. This makes it straightforward to verify coverage and trace failures to requirements.

### Spec File Naming

Organize spec files by feature area, with one file per story or per closely related group of stories:

```
spec/
  billing/
    retry_expired_payments_spec.cr      # Story: retry expired payments
    generate_monthly_invoices_spec.cr   # Story: generate monthly invoices
  onboarding/
    create_account_spec.cr              # Story: create account
    verify_email_spec.cr                # Story: verify email
  spec_helper.cr
```

### Describe Blocks Reference Story IDs

Include the story identifier in your top-level describe block so that test output maps directly to the feature story document:

```crystal
describe "Story 3.2 -- Retry expired payment methods" do
  it "retries each expired customer" do
    # ...
  end

  it "skips already-retried customers" do
    # ...
  end
end
```

### Coverage Tables in Feature Story Docs

Each feature story document includes a test mapping table that lists every acceptance criterion and the spec that covers it:

| Acceptance Criterion | Spec File | Describe / It Block |
|---------------------|-----------|-------------------|
| Expired cards are retried | `spec/billing/retry_expired_payments_spec.cr` | "retries each expired customer" |
| Valid cards are skipped | `spec/billing/retry_expired_payments_spec.cr` | "skips customers with valid payment methods" |
| Failures are recorded | `spec/billing/retry_expired_payments_spec.cr` | "records failures for customers that could not be retried" |

## Native App Testing

Amber patterns work outside of the HTTP server. Projects like Scribe use Amber's controllers, models, process managers, and configuration system for a native macOS menu bar app without ever starting `Amber::Server`.

### Process Managers Are Framework-Agnostic

Because process managers receive all dependencies through `initialize` and expose results as properties, the exact same test patterns work whether the app is a web server, a native desktop app, or a mobile companion app:

```crystal
# This spec is identical whether the host is a web app or a native app
describe Transcription::ProcessAudioFile do
  it "produces a transcript from a WAV file" do
    pm = Transcription::ProcessAudioFile.new(audio_path: "/tmp/test.wav")
    pm.perform
    pm.transcript.should_not be_empty
  end
end
```

### Asset Pipeline test_id Integration

When building cross-platform UI with the AssetPipeline, set `test_id` on views in Crystal. The test_id maps to the native test attribute on each platform (see the AssetPipeline Testing Guide for the full mapping table). This lets you write platform UI tests (XCUITest, Compose) that query elements by the same identifier you defined in Crystal.

```crystal
button = UI::Button.new
button.title = "Record"
button.test_id = "7.1-record-button"
```

The XCUITest, Compose UI test, or browser test then queries this identifier using the platform-native method, without needing to know how the Crystal layout code is structured.

### Test Layers for Native Apps

Native apps follow the same three-layer test strategy as web apps:

- **Layer 1 -- Crystal specs:** Test process managers, models, and view properties directly. No hardware, no UI framework.
- **Layer 2 -- Platform UI tests:** XCUITest (Apple) or Compose instrumented tests (Android) that interact with the running app and query elements by test_id.
- **Layer 3 -- End-to-end scripts:** Shell scripts that build, deploy, and run Layer 2 tests on simulators or devices.
