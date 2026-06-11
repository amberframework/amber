# Action Helpers

Amber V2 includes a comprehensive set of view helpers that are available in all controllers and ECR templates. These helpers generate HTML elements with proper escaping, CSRF protection, and semantic markup.

All helpers are included automatically via `Amber::Controller::Base`.

## FormHelpers

Generate HTML form elements with automatic CSRF token inclusion and method override support.

### form_for

Generates a `<form>` tag with automatic CSRF token inclusion. For non-GET/POST methods (PUT, PATCH, DELETE), a hidden `_method` field is emitted.

```crystal
form_for("/users", method: "POST") { "<input />" }
# => <form action="/users" method="POST">
#      <input type="hidden" name="_csrf" ... />
#      <input />
#    </form>

form_for("/users/1", method: "PATCH") { "<input />" }
# => <form action="/users/1" method="POST">
#      <input type="hidden" name="_method" value="PATCH" ... />
#      <input type="hidden" name="_csrf" ... />
#      <input />
#    </form>
```

In an ECR template:

```ecr
<%= form_for("/users", method: "POST") { %>
  <div class="form-group">
    <%= label("name") %>
    <%= text_field("name", class: "form-control") %>
  </div>
  <div class="form-group">
    <%= label("email") %>
    <%= email_field("email", class: "form-control") %>
  </div>
  <%= submit_button("Create User", class: "btn btn-primary") %>
<% } %>
```

### Input Fields

```crystal
text_field("name")
# => <input type="text" name="name" id="name" />

text_field("name", value: "John", class: "form-control")
# => <input type="text" name="name" id="name" value="John" class="form-control" />

email_field("email")
# => <input type="email" name="email" id="email" />

password_field("password")
# => <input type="password" name="password" id="password" />

number_field("quantity", value: 1)
# => <input type="number" name="quantity" id="quantity" value="1" />

hidden_field("user_id", "42")
# => <input type="hidden" name="user_id" id="user_id" value="42" />
```

### text_area

```crystal
text_area("bio")
# => <textarea name="bio" id="bio"></textarea>

text_area("bio", value: "Hello world", rows: "5")
# => <textarea name="bio" id="bio" rows="5">Hello world</textarea>
```

### select_field

Accepts an array of strings or an array of `{label, value}` tuples:

```crystal
select_field("color", ["Red", "Blue", "Green"])
# => <select name="color" id="color">
#      <option value="Red">Red</option>
#      <option value="Blue">Blue</option>
#      <option value="Green">Green</option>
#    </select>

select_field("color", [{"Red", "red"}, {"Blue", "blue"}], selected: "blue")
# => <select name="color" id="color">
#      <option value="red">Red</option>
#      <option value="blue" selected>Blue</option>
#    </select>
```

### checkbox and radio_button

```crystal
checkbox("remember_me")
# => <input type="checkbox" name="remember_me" id="remember_me" />

checkbox("terms", checked: true)
# => <input type="checkbox" name="terms" id="terms" checked />

radio_button("color", "red")
# => <input type="radio" name="color" id="color_red" value="red" />

radio_button("color", "blue", checked: true)
# => <input type="radio" name="color" id="color_blue" value="blue" checked />
```

### label

```crystal
label("email")
# => <label for="email">Email</label>

label("email", text: "Your Email Address")
# => <label for="email">Your Email Address</label>
```

### submit_button

```crystal
submit_button
# => <input type="submit" value="Submit" />

submit_button("Save Changes", class: "btn btn-primary")
# => <input type="submit" value="Save Changes" class="btn btn-primary" />
```

## URLHelpers

Generate anchor tags and navigation elements.

### link_to

```crystal
link_to("Home", "/")
# => <a href="/">Home</a>

link_to("Profile", "/users/1", class: "nav-link")
# => <a href="/users/1" class="nav-link">Profile</a>
```

### button_to

Generates a form containing a single submit button. Useful for delete links and other actions that should not be plain anchor tags:

```crystal
button_to("Delete", "/users/1", method: "DELETE")
# => <form action="/users/1" method="POST" class="button_to">
#      <input type="hidden" name="_method" value="DELETE" ... />
#      <input type="hidden" name="_csrf" ... />
#      <input type="submit" value="Delete" />
#    </form>
```

### mail_to

```crystal
mail_to("support@example.com")
# => <a href="mailto:support@example.com">support@example.com</a>

mail_to("support@example.com", text: "Contact Us")
# => <a href="mailto:support@example.com">Contact Us</a>
```

### link_back

Generates a link to the previous page using the `Referer` header, falling back to `"#"` if no referer is present:

```crystal
link_back
# => <a href="/previous-page">Back</a>

link_back(text: "Go Back", class: "btn")
# => <a href="/previous-page" class="btn">Go Back</a>
```

## AssetHelpers

Generate HTML tags for images, stylesheets, and JavaScript files.

### image_tag

```crystal
image_tag("/images/logo.png")
# => <img src="/images/logo.png" />

image_tag("/images/logo.png", alt: "Logo", width: "200")
# => <img src="/images/logo.png" alt="Logo" width="200" />
```

### stylesheet_link_tag

```crystal
stylesheet_link_tag("/css/app.css")
# => <link rel="stylesheet" href="/css/app.css" media="screen" />

stylesheet_link_tag("/css/print.css", media: "print")
# => <link rel="stylesheet" href="/css/print.css" media="print" />
```

### javascript_include_tag

```crystal
javascript_include_tag("/js/app.js")
# => <script src="/js/app.js"></script>

javascript_include_tag("/js/app.js", defer: true)
# => <script src="/js/app.js" defer></script>
```

### favicon_tag

```crystal
favicon_tag
# => <link rel="icon" type="image/x-icon" href="/favicon.ico" />

favicon_tag("/images/icon.png")
# => <link rel="icon" type="image/x-icon" href="/images/icon.png" />
```

## TagHelpers

Low-level HTML tag generation helpers.

### tag

Generates a self-closing HTML tag:

```crystal
tag("br")
# => <br />

tag("img", src: "/logo.png", alt: "Logo")
# => <img src="/logo.png" alt="Logo" />

tag("input", type: "text", name: "email", required: true)
# => <input type="text" name="email" required />
```

### content_tag

Generates an HTML tag with content (string or block):

```crystal
content_tag("p", "Hello")
# => <p>Hello</p>

content_tag("div", "Note", class: "alert")
# => <div class="alert">Note</div>

content_tag("ul", class: "nav") { "<li>Item 1</li><li>Item 2</li>" }
# => <ul class="nav"><li>Item 1</li><li>Item 2</li></ul>
```

Boolean attributes: `true` produces a valueless attribute (e.g., `disabled`), `false` and `nil` values are omitted.

## TextHelpers

Text manipulation helpers for views.

### truncate

```crystal
truncate("Hello World", length: 8)
# => "Hello..."

truncate("Hello World", length: 8, omission: ">>")
# => "Hello >>"

truncate("Hi", length: 10)
# => "Hi"
```

### pluralize

```crystal
pluralize(1, "person")
# => "1 person"

pluralize(2, "person")
# => "2 persons"

pluralize(2, "person", "people")
# => "2 people"

pluralize(0, "item")
# => "0 items"
```

### highlight

Wraps occurrences of a phrase in an HTML tag (case-insensitive):

```crystal
highlight("Hello World", "World")
# => "Hello <mark>World</mark>"

highlight("You found it", "found", tag: "em")
# => "You <em>found</em> it"
```

### simple_format

Converts newlines to `<br />` tags and wraps paragraphs in `<p>` tags:

```crystal
simple_format("Hello\nWorld")
# => "<p>Hello<br />World</p>"

simple_format("Para1\n\nPara2")
# => "<p>Para1</p><p>Para2</p>"
```

### word_wrap

```crystal
word_wrap("A very long sentence that needs wrapping", line_width: 20)
```

### strip_tags

Removes all HTML tags from a string:

```crystal
strip_tags("<p>Hello <b>World</b></p>")
# => "Hello World"
```

### escape_html

```crystal
escape_html("<script>alert('xss')</script>")
# => "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
```

## NumberHelpers

Number formatting helpers for views.

### number_with_delimiter

```crystal
number_with_delimiter(1234567)
# => "1,234,567"

number_with_delimiter(1234.5)
# => "1,234.5"

number_with_delimiter(1234567, delimiter: ".")
# => "1.234.567"
```

### number_to_currency

```crystal
number_to_currency(1234.5)
# => "$1,234.50"

number_to_currency(1234.5, unit: "EUR")
# => "EUR1,234.50"

number_to_currency(1234.567, precision: 3)
# => "$1,234.567"
```

### number_to_percentage

```crystal
number_to_percentage(75.5)
# => "75.5%"

number_to_percentage(75.567, precision: 2)
# => "75.57%"
```

### number_to_human_size

```crystal
number_to_human_size(500)
# => "500 Bytes"

number_to_human_size(1024)
# => "1.00 KB"

number_to_human_size(1048576)
# => "1.00 MB"

number_to_human_size(1073741824)
# => "1.00 GB"
```

## Using Helpers in ECR Templates

All helpers are available directly in ECR templates because they are included in the controller:

```ecr
<html>
<head>
  <%= stylesheet_link_tag("/css/app.css") %>
  <%= javascript_include_tag("/js/app.js", defer: true) %>
  <%= favicon_tag %>
</head>
<body>
  <nav>
    <%= link_to("Home", "/", class: "nav-link") %>
    <%= link_to("About", "/about", class: "nav-link") %>
  </nav>

  <h1>Users (<%= pluralize(@users.size, "user") %>)</h1>

  <%= form_for("/users", method: "POST") { %>
    <%= label("name") %>
    <%= text_field("name", class: "form-control") %>
    <%= label("email") %>
    <%= email_field("email", class: "form-control") %>
    <%= submit_button("Create", class: "btn btn-primary") %>
  <% } %>

  <p>Total sales: <%= number_to_currency(@total_sales) %></p>
  <p>Disk usage: <%= number_to_human_size(@disk_bytes) %></p>
</body>
</html>
```

## Source Files

- `src/amber/controller/helpers/form_helpers.cr` -- FormHelpers module
- `src/amber/controller/helpers/url_helpers.cr` -- URLHelpers module
- `src/amber/controller/helpers/asset_helpers.cr` -- AssetHelpers module
- `src/amber/controller/helpers/tag_helpers.cr` -- TagHelpers module
- `src/amber/controller/helpers/text_helpers.cr` -- TextHelpers module
- `src/amber/controller/helpers/number_helpers.cr` -- NumberHelpers module
