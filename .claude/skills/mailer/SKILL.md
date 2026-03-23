---
name: amber-mailer
description: Amber V2 mailer — email composition, SMTP adapter, memory adapter for testing, fluent API
user-invocable: false
---

# Amber Mailer

The mailer system provides email composition and delivery with an adapter pattern for pluggable backends. Ships with a memory adapter for testing and an SMTP adapter for production.

## Defining a Mailer

Inherit from `Amber::Mailer::Base` and implement `html_body` and `text_body`. Both methods return `String?` -- return `nil` to omit that content type.

```crystal
class WelcomeMailer < Amber::Mailer::Base
  def initialize(@user_name : String, @user_email : String)
  end

  def html_body : String?
    "<h1>Welcome, #{HTML.escape(@user_name)}!</h1><p>Thanks for signing up.</p>"
  end

  def text_body : String?
    "Welcome, #{@user_name}! Thanks for signing up."
  end
end
```

Mailers are plain Crystal classes. Pass any data they need through `initialize`.

## Email Composition -- Fluent API

All setter methods return `self` for chaining. Call `deliver` at the end to send.

```crystal
WelcomeMailer.new("Alice", "alice@example.com")
  .to("alice@example.com")
  .from("hello@myapp.com")
  .subject("Welcome to MyApp!")
  .deliver
```

### Available Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `to` | `to(*addresses : String) : self` | Set recipient addresses (replaces previous) |
| `from` | `from(address : String) : self` | Set sender address (overrides `default_from` config) |
| `subject` | `subject(text : String) : self` | Set subject line |
| `cc` | `cc(*addresses : String) : self` | Set CC recipients (replaces previous) |
| `bcc` | `bcc(*addresses : String) : self` | Set BCC recipients (replaces previous) |
| `reply_to` | `reply_to(address : String) : self` | Set Reply-To address |
| `header` | `header(name : String, value : String) : self` | Add a custom MIME header |
| `attach` | `attach(filename : String, content : Bytes, mime_type : String = "application/octet-stream") : self` | Attach binary content |
| `attach_file` | `attach_file(path : String, filename : String? = nil, mime_type : String = "application/octet-stream") : self` | Attach a file from disk |
| `build` | `build : Email` | Build the `Email` struct without delivering |
| `deliver` | `deliver : DeliveryResult` | Build and deliver via the configured adapter |

### Multiple Recipients, CC, BCC

```crystal
NotificationMailer.new(message)
  .to("alice@example.com", "bob@example.com")
  .cc("manager@example.com")
  .bcc("audit@example.com")
  .from("notifications@myapp.com")
  .subject("New notification")
  .deliver
```

### Attachments

```crystal
ReportMailer.new(report)
  .to("boss@example.com")
  .subject("Monthly Report")
  .attach("report.csv", csv_data.to_slice, "text/csv")
  .attach_file("tmp/chart.png", mime_type: "image/png")
  .deliver
```

### Custom Headers

```crystal
mailer.header("X-Mailer", "MyApp/1.0")
      .header("X-Priority", "1")
      .deliver
```

## Delivery Result

`deliver` returns a `DeliveryResult` struct:

```crystal
result = mailer.deliver

if result.is_successful
  # Email sent
else
  Log.error { "Email failed: #{result.error}" }
end
```

## Configuration

### Via `Amber::Mailer::Configuration` (runtime)

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

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `adapter` | `Symbol` | `:memory` | `:memory` or `:smtp` |
| `smtp_host` | `String` | `"localhost"` | SMTP server hostname |
| `smtp_port` | `Int32` | `587` | SMTP server port |
| `smtp_username` | `String?` | `nil` | AUTH LOGIN username |
| `smtp_password` | `String?` | `nil` | AUTH LOGIN password |
| `use_tls` | `Bool` | `true` | Enable STARTTLS |
| `default_from` | `String` | `"noreply@example.com"` | Default sender when `from` is not called |
| `helo_domain` | `String` | `"localhost"` | Domain for EHLO command |

### Via YAML (MailerConfig)

The typed configuration system loads mailer settings from YAML with environment variable overrides:

```yaml
mailer:
  adapter: smtp
  default_from: "noreply@myapp.com"
  smtp:
    host: smtp.example.com
    port: 587
    username: ~
    password: ~
    use_tls: true
    helo_domain: myapp.com
```

`MailerConfig` properties:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `adapter` | `String` | `"memory"` | `"memory"` or `"smtp"` |
| `default_from` | `String` | `"noreply@example.com"` | Default sender address |
| `smtp` | `SMTPConfig` | (see below) | Nested SMTP settings |

`SMTPConfig` properties:

| Property | Type | Default | Purpose |
|----------|------|---------|---------|
| `host` | `String` | `"localhost"` | SMTP server hostname |
| `port` | `Int32` | `587` | SMTP server port |
| `username` | `String?` | `nil` | AUTH LOGIN username |
| `password` | `String?` | `nil` | AUTH LOGIN password |
| `use_tls` | `Bool` | `true` | Enable STARTTLS |
| `helo_domain` | `String` | `"localhost"` | Domain for EHLO command |

`MailerConfig#validate!` raises `ConfigurationError` if the adapter is `"smtp"` and the host is empty or the port is out of range.

## SMTP Adapter

The `SMTPAdapter` implements the full SMTP protocol flow:

1. TCP connect to host:port
2. Read server greeting (220)
3. EHLO handshake
4. STARTTLS upgrade (if `use_tls` is true)
5. AUTH LOGIN (if username and password are provided)
6. MAIL FROM / RCPT TO / DATA envelope
7. MIME message transmission
8. QUIT

Errors at any step produce a `DeliveryResult` with `is_successful: false` and a descriptive error message. Connection and socket errors are caught and reported without raising.

## Memory Adapter (Testing)

The `MemoryAdapter` stores delivered emails in a thread-safe class-level array. Use it in tests to verify email content without sending.

```crystal
# In spec_helper or test setup
Amber::Mailer::Configuration.configure do |config|
  config.adapter = :memory
end

# In each test
Amber::Mailer::MemoryAdapter.clear

WelcomeMailer.new("Alice", "alice@example.com")
  .to("alice@example.com")
  .subject("Welcome!")
  .deliver

# Assertions
Amber::Mailer::MemoryAdapter.count.should eq 1

email = Amber::Mailer::MemoryAdapter.last.not_nil!
email.to.should eq ["alice@example.com"]
email.subject.should eq "Welcome!"
email.html_body.should contain "Welcome"
```

### MemoryAdapter Class Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.deliveries` | `Array(Email)` | All stored emails (returns a copy) |
| `.last` | `Email?` | Most recent email or nil |
| `.count` | `Int32` | Number of stored emails |
| `.clear` | `Nil` | Remove all stored emails |

All methods are mutex-synchronized for thread safety.

## Sending Emails from Controllers

```crystal
class RegistrationController < Amber::Controller::Base
  def create
    user = create_user(params)

    result = WelcomeMailer.new(user.name, user.email)
      .to(user.email)
      .subject("Welcome to MyApp!")
      .deliver

    unless result.is_successful
      Log.error { "Welcome email failed: #{result.error}" }
    end

    redirect_to action: :index, flash: {"notice" => "Account created!"}
  end
end
```

If no `from` address is set on the mailer, the `default_from` from configuration is used automatically.

## Template Rendering for Email Bodies

Mailer bodies are plain Crystal strings. Use string interpolation, `String.build`, or ECR for complex templates.

### String Interpolation

```crystal
class OrderMailer < Amber::Mailer::Base
  def initialize(@order_id : Int64, @total : Float64)
  end

  def html_body : String?
    "<h1>Order ##{@order_id}</h1><p>Total: $#{"%.2f" % @total}</p>"
  end

  def text_body : String?
    "Order ##{@order_id} - Total: $#{"%.2f" % @total}"
  end
end
```

### ECR Templates

```crystal
require "ecr"

class OrderMailer < Amber::Mailer::Base
  def initialize(@order_id : Int64, @list_of_items : Array(Item))
  end

  def html_body : String?
    String.build do |io|
      ECR.embed("src/views/mailers/order.ecr", io)
    end
  end

  def text_body : String?
    String.build do |io|
      ECR.embed("src/views/mailers/order_text.ecr", io)
    end
  end
end
```

In `src/views/mailers/order.ecr`:
```ecr
<h1>Order #<%= @order_id %></h1>
<table>
  <% @list_of_items.each do |item| %>
    <tr>
      <td><%= HTML.escape(item.name) %></td>
      <td>$<%= "%.2f" % item.price %></td>
    </tr>
  <% end %>
</table>
```

## Custom Delivery Adapters

Inherit from `DeliveryAdapter` and implement `deliver`:

```crystal
class SendGridAdapter < Amber::Mailer::DeliveryAdapter
  def deliver(email : Amber::Mailer::Email) : Amber::Mailer::DeliveryResult
    # Send via SendGrid API
    Amber::Mailer::DeliveryResult.new(is_successful: true)
  end
end
```

## Email Struct

The `Email` struct holds the fully composed message. Accessible via `build` or inside adapters.

| Property | Type | Purpose |
|----------|------|---------|
| `to` | `Array(String)` | Recipient addresses |
| `from` | `String` | Sender address |
| `subject` | `String` | Subject line |
| `cc` | `Array(String)` | CC recipients |
| `bcc` | `Array(String)` | BCC recipients |
| `reply_to` | `String?` | Reply-To address |
| `html_body` | `String?` | HTML content |
| `text_body` | `String?` | Plain text content |
| `headers` | `Hash(String, String)` | Custom headers |
| `attachments` | `Array(Attachment)` | File attachments |

Methods: `to_mime : String` generates RFC 2045 MIME output, `all_recipients : Array(String)` returns to + cc + bcc.

## Key Source Files

| File | Contains |
|------|----------|
| `src/amber/mailer.cr` | Module require and documentation |
| `src/amber/mailer/base.cr` | `Amber::Mailer::Base` abstract class with fluent API |
| `src/amber/mailer/email.cr` | `Email`, `Attachment`, `DeliveryResult` structs |
| `src/amber/mailer/delivery_adapter.cr` | `DeliveryAdapter` abstract class |
| `src/amber/mailer/smtp_adapter.cr` | `SMTPAdapter` with full SMTP protocol |
| `src/amber/mailer/memory_adapter.cr` | `MemoryAdapter` for testing |
| `src/amber/mailer/configuration.cr` | `Configuration` singleton with `build_adapter` |
| `src/amber/mailer/mime.cr` | `MimeBuilder` for RFC 2045 MIME generation |
| `src/amber/configuration/mailer_config.cr` | `MailerConfig` and `SMTPConfig` YAML structs |
