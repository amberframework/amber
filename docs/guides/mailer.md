# Mailer

Amber::Mailer provides a complete email delivery system with an adapter pattern for pluggable delivery backends. It ships with a memory adapter for testing and an SMTP adapter for production use. Mailers use a fluent API for composing messages, support file attachments, and generate RFC 2045-compliant MIME messages.

## Quick Start

```crystal
class WelcomeMailer < Amber::Mailer::Base
  def initialize(@user_name : String)
  end

  def html_body : String?
    "<h1>Welcome, #{HTML.escape(@user_name)}!</h1>"
  end

  def text_body : String?
    "Welcome, #{@user_name}!"
  end
end

# Send an email
WelcomeMailer.new("Alice")
  .to("alice@example.com")
  .from("hello@myapp.com")
  .subject("Welcome to MyApp!")
  .deliver
```

## Defining Mailers

Every mailer must inherit from `Amber::Mailer::Base` and implement the abstract `html_body` and `text_body` methods. Return `nil` from either method to send only the other format.

```crystal
class OrderConfirmation < Amber::Mailer::Base
  def initialize(@order_id : Int64, @customer_name : String, @total : Float64)
  end

  def html_body : String?
    <<-HTML
    <h1>Order Confirmation</h1>
    <p>Thank you, #{HTML.escape(@customer_name)}!</p>
    <p>Order ##{@order_id} - Total: $#{sprintf("%.2f", @total)}</p>
    HTML
  end

  def text_body : String?
    <<-TEXT
    Order Confirmation
    Thank you, #{@customer_name}!
    Order ##{@order_id} - Total: $#{sprintf("%.2f", @total)}
    TEXT
  end
end
```

### HTML-Only or Text-Only Emails

Return `nil` from the method you do not want to include:

```crystal
class HtmlOnlyMailer < Amber::Mailer::Base
  def html_body : String?
    "<h1>HTML content only</h1>"
  end

  def text_body : String?
    nil  # No text alternative
  end
end
```

## Fluent API

All setter methods return `self` to enable method chaining:

```crystal
OrderConfirmation.new(order_id: 123_i64, customer_name: "Alice", total: 49.99)
  .to("alice@example.com", "billing@example.com")
  .from("orders@myapp.com")
  .subject("Order #123 Confirmed")
  .cc("manager@myapp.com")
  .bcc("archive@myapp.com")
  .reply_to("support@myapp.com")
  .header("X-Mailer", "MyApp/2.0")
  .deliver
```

### Available Methods

| Method | Description |
|--------|-------------|
| `to(*addresses)` | Set recipient addresses (replaces previous) |
| `from(address)` | Set sender address (overrides default_from) |
| `subject(text)` | Set subject line |
| `cc(*addresses)` | Set CC recipients (replaces previous) |
| `bcc(*addresses)` | Set BCC recipients (replaces previous) |
| `reply_to(address)` | Set Reply-To address |
| `header(name, value)` | Add a custom MIME header |
| `attach(filename, content, mime_type)` | Attach binary content |
| `attach_file(path, filename, mime_type)` | Attach a file from disk |
| `build` | Build the Email struct without sending |
| `deliver` | Build and deliver the email |

## Attachments

### Binary Content

```crystal
pdf_bytes = File.read("invoice.pdf").to_slice

InvoiceMailer.new(invoice_id: 456_i64)
  .to("customer@example.com")
  .subject("Your Invoice")
  .attach("invoice-456.pdf", pdf_bytes, "application/pdf")
  .deliver
```

### File from Disk

```crystal
InvoiceMailer.new(invoice_id: 456_i64)
  .to("customer@example.com")
  .subject("Your Invoice")
  .attach_file("tmp/invoices/456.pdf", mime_type: "application/pdf")
  .deliver
```

If `filename` is not provided to `attach_file`, the basename of the path is used automatically.

Attachments are base64-encoded in the generated MIME message and included as separate MIME parts with `Content-Disposition: attachment` headers.

## Configuration

Configure the mailer system using the singleton Configuration:

```crystal
Amber::Mailer::Configuration.configure do |config|
  config.adapter = :smtp
  config.smtp_host = "smtp.example.com"
  config.smtp_port = 587
  config.smtp_username = ENV["SMTP_USER"]
  config.smtp_password = ENV["SMTP_PASS"]
  config.use_tls = true
  config.default_from = "noreply@myapp.com"
  config.helo_domain = "myapp.com"
end
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `adapter` | `:memory` | Delivery backend (`:memory` or `:smtp`) |
| `smtp_host` | `"localhost"` | SMTP server hostname |
| `smtp_port` | `587` | SMTP server port |
| `smtp_username` | `nil` | SMTP AUTH LOGIN username |
| `smtp_password` | `nil` | SMTP AUTH LOGIN password |
| `use_tls` | `true` | Enable STARTTLS encryption |
| `default_from` | `"noreply@example.com"` | Default sender when `from` is not called |
| `helo_domain` | `"localhost"` | Domain sent in EHLO command |

### YAML Configuration

Mailer settings can be placed in your environment YAML files:

```yaml
mailer:
  adapter: "smtp"
  default_from: "noreply@myapp.com"
  smtp:
    host: "smtp.example.com"
    port: 587
    username: "user@example.com"
    password: "secret"
    use_tls: true
    helo_domain: "myapp.com"
```

### Environment Variable Overrides

```bash
AMBER_MAILER_ADAPTER=smtp
AMBER_MAILER_DEFAULT_FROM=noreply@myapp.com
AMBER_MAILER_SMTP_HOST=smtp.example.com
AMBER_MAILER_SMTP_PORT=587
AMBER_MAILER_SMTP_USERNAME=user@example.com
AMBER_MAILER_SMTP_PASSWORD=secret
AMBER_MAILER_SMTP_USE_TLS=true
AMBER_MAILER_SMTP_HELO_DOMAIN=myapp.com
```

## Delivery Adapters

### MemoryAdapter (Default)

Stores all delivered emails in a thread-safe class-level array. Ideal for testing and development.

```crystal
# Clear stored emails
Amber::Mailer::MemoryAdapter.clear

# Check deliveries
Amber::Mailer::MemoryAdapter.count       # => 0
Amber::Mailer::MemoryAdapter.deliveries  # => Array(Email)
Amber::Mailer::MemoryAdapter.last        # => Email?
```

### SMTPAdapter

Delivers emails via the SMTP protocol. Supports STARTTLS encryption and AUTH LOGIN authentication.

The SMTP protocol flow is:

1. Connect to SMTP server
2. Read server greeting (220)
3. Send EHLO
4. Optionally upgrade to TLS via STARTTLS
5. Re-send EHLO after TLS upgrade
6. Authenticate via AUTH LOGIN if credentials are provided
7. Send MAIL FROM, RCPT TO, DATA commands
8. Send the MIME message
9. Send QUIT

### Writing a Custom Adapter

Inherit from `Amber::Mailer::DeliveryAdapter` and implement the `deliver` method:

```crystal
class SendGridAdapter < Amber::Mailer::DeliveryAdapter
  def initialize(@api_key : String)
  end

  def deliver(email : Email) : DeliveryResult
    # Implement your delivery logic
    response = HTTP::Client.post(
      "https://api.sendgrid.com/v3/mail/send",
      headers: HTTP::Headers{"Authorization" => "Bearer #{@api_key}"},
      body: build_sendgrid_payload(email).to_json
    )

    if response.status_code == 202
      DeliveryResult.new(is_successful: true)
    else
      DeliveryResult.new(is_successful: false, error: response.body)
    end
  end
end
```

## Building Without Delivering

Use `build` to construct the `Email` struct without sending it. This is useful for inspecting the email or passing it to a background job:

```crystal
mailer = WelcomeMailer.new("Alice")
  .to("alice@example.com")
  .subject("Welcome!")

email = mailer.build
puts email.to        # => ["alice@example.com"]
puts email.subject   # => "Welcome!"
puts email.to_mime   # => Full MIME message string
```

## Testing

Use the MemoryAdapter to verify emails were sent correctly in your specs:

```crystal
describe OrderConfirmation do
  before_each do
    Amber::Mailer::Configuration.reset
    Amber::Mailer::MemoryAdapter.clear
  end

  it "sends a confirmation email" do
    OrderConfirmation.new(
      order_id: 123_i64,
      customer_name: "Alice",
      total: 49.99
    )
      .to("alice@example.com")
      .subject("Order #123 Confirmed")
      .deliver

    Amber::Mailer::MemoryAdapter.count.should eq(1)

    email = Amber::Mailer::MemoryAdapter.last.not_nil!
    email.to.should eq(["alice@example.com"])
    email.subject.should eq("Order #123 Confirmed")
    email.html_body.not_nil!.should contain("Alice")
  end

  it "includes attachments" do
    content = "test content".to_slice

    WelcomeMailer.new("Alice")
      .to("alice@example.com")
      .subject("Welcome!")
      .attach("test.txt", content, "text/plain")
      .deliver

    email = Amber::Mailer::MemoryAdapter.last.not_nil!
    email.attachments.size.should eq(1)
    email.attachments[0].filename.should eq("test.txt")
  end
end
```

## Common Patterns

### Sending Email from a Controller

```crystal
class UsersController < ApplicationController
  def create
    user = User.create!(params)

    WelcomeMailer.new(user.name)
      .to(user.email)
      .subject("Welcome to MyApp!")
      .deliver

    redirect_to "/users/#{user.id}"
  end
end
```

### Sending Email via a Background Job

```crystal
class SendEmailJob < Amber::Jobs::Job
  include JSON::Serializable

  property user_name : String
  property user_email : String

  def initialize(@user_name : String, @user_email : String)
  end

  def perform
    WelcomeMailer.new(@user_name)
      .to(@user_email)
      .subject("Welcome!")
      .deliver
  end
end

# In the controller
SendEmailJob.new(user_name: user.name, user_email: user.email).enqueue
```

## Source Files

- `src/amber/mailer.cr` -- Module entry point
- `src/amber/mailer/base.cr` -- Abstract Base mailer with fluent API
- `src/amber/mailer/email.cr` -- Email struct, Attachment struct, DeliveryResult
- `src/amber/mailer/delivery_adapter.cr` -- Abstract DeliveryAdapter base class
- `src/amber/mailer/memory_adapter.cr` -- In-memory adapter for testing
- `src/amber/mailer/smtp_adapter.cr` -- SMTP delivery adapter
- `src/amber/mailer/mime.cr` -- MIME message builder
- `src/amber/mailer/configuration.cr` -- Mailer configuration singleton
