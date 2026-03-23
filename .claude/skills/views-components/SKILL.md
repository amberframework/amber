---
name: amber-views-components
description: Amber V2 views and templates — ECR rendering, layouts, partials, tag helpers, form helpers, text helpers, number helpers, URL helpers, asset helpers
user-invocable: false
---

# Amber V2 Views and Components

## ECR Templates

Amber V2 uses ECR (Embedded Crystal) as its only template engine. Kilt and Slang have been removed. ECR is part of the Crystal standard library and requires no external dependencies.

ECR syntax:

```ecr
<%# This is a comment %>
<% crystal_code_here %>
<%= expression_to_output %>
```

All controller helpers (tag, form, text, number, URL, asset, markdown, CSRF) are available directly inside ECR templates because the template is compiled in the context of the controller instance.

## The render Macro

The `render` macro is defined in `Amber::Controller::Helpers::Render`. It accepts four named parameters:

| Parameter  | Type              | Default       | Purpose                                          |
|------------|-------------------|---------------|--------------------------------------------------|
| `template` | `StringLiteral`   | `nil`         | Template filename to render                      |
| `layout`   | `Bool \| String`  | `true`        | Layout to wrap the template in                   |
| `partial`  | `StringLiteral`   | `nil`         | Partial filename to render (no layout applied)   |
| `path`     | `StringLiteral`   | `"src/views"` | Base path for template resolution                |

Either `template` or `partial` must be provided. If neither is given, a compile-time error is raised.

### Basic usage in a controller action

```crystal
class PostController < Amber::Controller::Base
  def index
    @list_of_posts = Post.all
    render(template: "index.ecr")
  end

  def show
    @post = Post.find(params[:id])
    render(template: "show.ecr")
  end
end
```

### Rendering with an explicit layout

```crystal
def index
  render(template: "index.ecr", layout: "admin.ecr")
end
```

### Rendering without a layout

```crystal
def api_data
  render(template: "data.ecr", layout: false)
end
```

### Rendering from a custom path

```crystal
def shared_view
  render(template: "shared/banner.ecr", path: "src/views")
end
```

## Template Path Conventions

When a short filename is provided (no `/` separator), the macro derives the subdirectory from the controller's source file path. The controller filename has `_controller.cr` or `.cr` stripped, and that becomes the view subdirectory.

For `PostController` defined in `src/controllers/post_controller.cr`:

- `render(template: "index.ecr")` resolves to `src/views/post/index.ecr`
- `render(template: "show.ecr")` resolves to `src/views/post/show.ecr`

When a path with `/` is provided, it is used relative to the `path` base:

- `render(template: "admin/dashboard.ecr")` resolves to `src/views/admin/dashboard.ecr`

## Layout System

The default layout is controlled by the `LAYOUT` constant, which defaults to `"application.ecr"`. The layout file is loaded from `src/views/layouts/`.

Inside a layout file, the rendered template content is available as the local variable `content`:

```ecr
<!-- src/views/layouts/application.ecr -->
<!DOCTYPE html>
<html>
<head>
  <title>My App</title>
  <%= stylesheet_link_tag("/css/app.css") %>
  <%= csrf_metatag %>
</head>
<body>
  <%= content %>
</body>
</html>
```

### Overriding the layout per controller

Set the `LAYOUT` constant inside the controller class:

```crystal
class AdminController < Amber::Controller::Base
  LAYOUT = "admin.ecr"

  def dashboard
    render(template: "dashboard.ecr")
  end
end
```

This renders `src/views/admin/dashboard.ecr` wrapped in `src/views/layouts/admin.ecr`.

### Disabling layouts for an entire controller

```crystal
class ApiController < Amber::Controller::Base
  LAYOUT = "false"

  def index
    render(template: "index.ecr")
  end
end
```

When `LAYOUT` is set to the string `"false"`, no layout wrapping occurs for any action in that controller. You can also disable the layout per-action with `layout: false` on the render call.

## Partials

Partials are rendered with `render(partial:)`. Partials never have a layout applied.

```crystal
def index
  render(template: "index.ecr")
end
```

Inside the template:

```ecr
<!-- src/views/post/index.ecr -->
<h1>Posts</h1>
<%= render(partial: "_post_list.ecr") %>
```

The partial resolves using the same directory logic as templates. For a partial in a different directory, include the path:

```ecr
<%= render(partial: "shared/_sidebar.ecr") %>
```

## Tag Helpers

Defined in `Amber::Controller::Helpers::TagHelpers`. Two methods for building HTML elements.

### tag (self-closing)

Builds a self-closing HTML tag.

```crystal
tag("br")                              # => "<br />"
tag("img", src: "/logo.png")           # => "<img src=\"/logo.png\" />"
tag("input", type: "text", name: "q")  # => "<input type=\"text\" name=\"q\" />"
tag("hr", class: "divider")            # => "<hr class=\"divider\" />"
```

### content_tag (with content)

Builds an HTML element with content. Accepts a content string or a block.

```crystal
content_tag("p", "Hello")                     # => "<p>Hello</p>"
content_tag("div", "Hi", class: "note")        # => "<div class=\"note\">Hi</div>"
content_tag("ul") { "<li>Item</li>" }          # => "<ul><li>Item</li></ul>"
content_tag("span", "Active", id: "status")    # => "<span id=\"status\">Active</span>"
```

### Attribute handling

All tag helpers share the same attribute rules:
- Boolean `true` values produce valueless attributes (e.g., `disabled`)
- `nil` and `false` values are omitted entirely
- All string values are HTML-escaped

```crystal
tag("input", type: "text", disabled: true, autofocus: false)
# => "<input type=\"text\" disabled />"
```

## Form Helpers

Defined in `Amber::Controller::Helpers::FormHelpers`. All output is HTML-escaped.

### form_for

Generates a `<form>` tag. Automatically includes a CSRF token for non-GET forms. For methods other than GET and POST, a hidden `_method` field is emitted and the form's actual method is set to POST.

```crystal
form_for("/users", method: "POST") do
  label("name") +
  text_field("name") +
  submit_button("Create")
end
```

```crystal
form_for("/users/1", method: "DELETE", class: "inline") do
  submit_button("Delete", class: "btn-danger")
end
# Emits: <form action="/users/1" method="POST" class="inline">
#          <input type="hidden" name="_method" id="_method" value="DELETE" />
#          [csrf_tag]
#          <input type="submit" value="Delete" class="btn-danger" />
#        </form>
```

### Input fields

```crystal
text_field("name")                          # => <input type="text" name="name" id="name" />
text_field("name", value: "John")           # includes value="John"
text_field("name", class: "form-control")   # includes class="form-control"

email_field("email")                        # => <input type="email" name="email" id="email" />
email_field("email", value: "a@b.com")      # includes value="a@b.com"

password_field("password")                  # => <input type="password" name="password" id="password" />
# password_field never includes a value attribute

number_field("quantity")                    # => <input type="number" name="quantity" id="quantity" />
number_field("quantity", value: 5)          # includes value="5"

hidden_field("token", "abc123")             # => <input type="hidden" name="token" id="token" value="abc123" />
```

### text_area

```crystal
text_area("bio")                            # => <textarea name="bio" id="bio"></textarea>
text_area("bio", value: "Hello")            # => <textarea name="bio" id="bio">Hello</textarea>
text_area("bio", rows: "5", cols: "40")     # includes rows and cols attributes
```

### select_field

Accepts an array of strings or an array of `{label, value}` tuples.

```crystal
select_field("color", [{"Red", "red"}, {"Blue", "blue"}], selected: "blue")
# => <select name="color" id="color">
#      <option value="red">Red</option>
#      <option value="blue" selected>Blue</option>
#    </select>

select_field("size", ["Small", "Medium", "Large"])
# Uses the string as both label and value
```

### checkbox and radio_button

```crystal
checkbox("remember_me")                     # => <input type="checkbox" name="remember_me" id="remember_me" />
checkbox("terms", checked: true)            # includes checked attribute

radio_button("color", "red")                # => <input type="radio" name="color" id="color_red" value="red" />
radio_button("color", "blue", checked: true)  # includes checked attribute
```

Radio button `id` is generated as `{name}_{value}` to allow multiple radio buttons for the same field.

### label

```crystal
label("email")                              # => <label for="email">Email</label>
label("email", text: "Your Email")          # => <label for="email">Your Email</label>
label("email", class: "required")           # includes class attribute
```

When no `text` is provided, the field name is capitalized automatically.

### submit_button

```crystal
submit_button                               # => <input type="submit" value="Submit" />
submit_button("Save")                       # => <input type="submit" value="Save" />
submit_button("Go", class: "btn-primary")   # includes class attribute
```

### Complete form example in ECR

```ecr
<%= form_for("/users", method: "POST", class: "user-form") do
  label("name") +
  text_field("name", value: @user.name, class: "input") +
  label("email", text: "Email Address") +
  email_field("email", value: @user.email, class: "input") +
  label("bio") +
  text_area("bio", value: @user.bio, rows: "4") +
  label("role") +
  select_field("role", [{"Admin", "admin"}, {"User", "user"}], selected: @user.role) +
  checkbox("is_active", checked: @user.is_active) +
  label("is_active", text: "Active account") +
  submit_button("Save User", class: "btn")
end %>
```

## Text Helpers

Defined in `Amber::Controller::Helpers::TextHelpers`.

### truncate

```crystal
truncate("Hello World", length: 8)                   # => "Hello..."
truncate("Hello World", length: 8, omission: ">>")   # => "Hello >>"
truncate("Hi", length: 10)                            # => "Hi"
truncate("Long text", length: 30)                     # default length is 30
```

### pluralize

```crystal
pluralize(1, "person")                # => "1 person"
pluralize(2, "person")                # => "2 people"  (default: appends "s")
pluralize(2, "person", "people")      # => "2 people"  (explicit plural)
pluralize(0, "item")                  # => "0 items"
```

Note: The default pluralization simply appends `"s"`. For irregular plurals, provide the explicit plural form as the third argument.

### highlight

Wraps occurrences of a phrase in an HTML tag. Case-insensitive matching. Both text and phrase are HTML-escaped before processing.

```crystal
highlight("Hello World", "World")                # => "Hello <mark>World</mark>"
highlight("Hello World", "world")                # => "Hello <mark>World</mark>"
highlight("You found it", "found", tag: "em")    # => "You <em>found</em> it"
```

### simple_format

Converts newlines to `<br />` and double-newlines to paragraph breaks. Text is HTML-escaped.

```crystal
simple_format("Hello\nWorld")       # => "<p>Hello<br />World</p>"
simple_format("Para1\n\nPara2")     # => "<p>Para1</p><p>Para2</p>"
```

### word_wrap

Wraps text at the specified line width (default 80).

```crystal
word_wrap("A very long sentence that goes on", line_width: 10)
```

### strip_tags

Removes all HTML tags from a string.

```crystal
strip_tags("<p>Hello <b>World</b></p>")       # => "Hello World"
strip_tags("<script>alert('xss')</script>")   # => "alert('xss')"
strip_tags("No tags here")                     # => "No tags here"
```

### escape_html

Escapes HTML entities. Delegates to `HTML.escape`.

```crystal
escape_html("<script>alert('xss')</script>")
# => "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
```

## Number Helpers

Defined in `Amber::Controller::Helpers::NumberHelpers`.

### number_with_delimiter

```crystal
number_with_delimiter(1234567)                   # => "1,234,567"
number_with_delimiter(1234.5)                    # => "1,234.5"
number_with_delimiter(1234567, delimiter: ".")   # => "1.234.567"
number_with_delimiter(-50000)                    # => "-50,000"
```

### number_to_currency

```crystal
number_to_currency(1234.5)                       # => "$1,234.50"
number_to_currency(1234.5, unit: "EUR")          # => "EUR1,234.50"
number_to_currency(1234.567, precision: 3)       # => "$1,234.567"
number_to_currency(-99.99)                       # => "-$99.99"
```

### number_to_percentage

```crystal
number_to_percentage(75.5)                       # => "75.5%"
number_to_percentage(75.567, precision: 2)       # => "75.57%"
```

### number_to_human_size

```crystal
number_to_human_size(0)          # => "0 Bytes"
number_to_human_size(500)        # => "500 Bytes"
number_to_human_size(1024)       # => "1.00 KB"
number_to_human_size(1048576)    # => "1.00 MB"
number_to_human_size(1073741824) # => "1.00 GB"
```

## URL Helpers

Defined in `Amber::Controller::Helpers::URLHelpers`.

### link_to

```crystal
link_to("Home", "/")                              # => "<a href=\"/\">Home</a>"
link_to("Profile", "/users/1", class: "nav-link") # includes class attribute
link_to("Docs", "/docs", target: "_blank")         # includes target attribute
```

### button_to

Generates a form containing a single submit button. Useful for actions like delete that should not be plain links. Includes CSRF token and method override automatically.

```crystal
button_to("Delete", "/users/1", method: "DELETE")
# => <form action="/users/1" method="POST" class="button_to">
#      <input type="hidden" name="_method" id="_method" value="DELETE" />
#      [csrf_tag]
#      <input type="submit" value="Delete" />
#    </form>

button_to("Archive", "/posts/1/archive", method: "PATCH", class: "btn")
```

### mail_to

```crystal
mail_to("user@example.com")                       # => "<a href=\"mailto:user@example.com\">user@example.com</a>"
mail_to("user@example.com", text: "Email us")     # => "<a href=\"mailto:user@example.com\">Email us</a>"
mail_to("support@app.com", class: "support-link")  # includes class attribute
```

### link_back

Generates a link to the previous page using the `Referer` header. Falls back to `"#"` when no referer is present.

```crystal
link_back                        # => "<a href=\"/previous-page\">Back</a>"
link_back(text: "Go Back")       # => "<a href=\"/previous-page\">Go Back</a>"
link_back(class: "back-link")    # includes class attribute
```

### Named route helpers

The controller base also provides `route_path` and `route_url` for named routes (see the routing skill for full details):

```crystal
route_path(:user, id: 1)    # => "/users/1"
route_url(:user, id: 1)     # => "https://example.com/users/1"
```

These are usable inside ECR templates:

```ecr
<a href="<%= route_path(:edit_user, id: @user.id) %>">Edit</a>
```

## Asset Helpers

Defined in `Amber::Controller::Helpers::AssetHelpers`.

### image_tag

```crystal
image_tag("/images/logo.png")                          # => "<img src=\"/images/logo.png\" />"
image_tag("/images/logo.png", alt: "Logo")             # includes alt attribute
image_tag("/photo.jpg", width: "200", height: "100")   # includes dimensions
```

### stylesheet_link_tag

Defaults to `media="screen"` unless a `media` attribute is explicitly provided.

```crystal
stylesheet_link_tag("/css/app.css")
# => "<link rel=\"stylesheet\" href=\"/css/app.css\" media=\"screen\" />"

stylesheet_link_tag("/css/print.css", media: "print")
# => "<link rel=\"stylesheet\" href=\"/css/print.css\" media=\"print\" />"
```

### javascript_include_tag

```crystal
javascript_include_tag("/js/app.js")
# => "<script src=\"/js/app.js\"></script>"

javascript_include_tag("/js/app.js", defer: true)
# => "<script src=\"/js/app.js\" defer></script>"

javascript_include_tag("/js/app.js", type: "module")
# => "<script src=\"/js/app.js\" type=\"module\"></script>"
```

### favicon_tag

```crystal
favicon_tag
# => "<link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\" />"

favicon_tag("/images/icon.png")
# => "<link rel=\"icon\" type=\"image/x-icon\" href=\"/images/icon.png\" />"
```

## Markdown Helper

Defined in `Amber::Controller::Helpers::MarkdownHelper`. Uses Amber's built-in Markdown renderer (no external dependency).

### Render a string

```crystal
render_markdown("# Hello")       # => "<h1>Hello</h1>\n"
render_markdown("**bold**")      # => "<p><strong>bold</strong></p>\n"
```

### Render a file

```crystal
render_markdown(file: "README.md")
render_markdown(file: "docs/guide.md")
```

### Options

Pass an `Amber::Markdown::Options` instance to control rendering behavior:

```crystal
options = Amber::Markdown::Options.new(
  gfm: true,           # GitHub Flavored Markdown (tables, strikethrough, etc.)
  toc: true,           # Generate anchor IDs on headings for table of contents
  smart: true,         # Smart quotes, en/em dashes, ellipses
  safe: true,          # Strip raw HTML from output
  source_pos: false,   # Add data-sourcepos attributes to block elements
  prettyprint: false,  # Add prettyprint class to code blocks
  base_url: nil,       # Resolve relative URLs against this base
  code_highlighter: nil # Custom syntax highlighting callback
)

render_markdown("# Hello **world**", options: options)
```

The `code_highlighter` option accepts a proc for syntax highlighting:

```crystal
highlighter = ->(code : String, language : String) {
  "<pre class=\"highlight #{language}\"><code>#{HTML.escape(code)}</code></pre>"
}

options = Amber::Markdown::Options.new(
  gfm: true,
  code_highlighter: highlighter
)

render_markdown(source, options: options)
```

### Usage in ECR templates

```ecr
<article>
  <%= render_markdown(@post.body) %>
</article>

<div class="docs">
  <%= render_markdown(file: "docs/getting-started.md", options: Amber::Markdown::Options.new(gfm: true, toc: true)) %>
</div>
```

## CSRF in Templates

Defined in `Amber::Controller::Helpers::CSRF`. These helpers delegate to `Amber::Pipe::CSRF`.

### csrf_tag

Outputs a hidden input field containing the CSRF token. Automatically included by `form_for` for non-GET forms.

```ecr
<form method="POST" action="/submit">
  <%= csrf_tag %>
  <!-- form fields -->
</form>
```

### csrf_metatag

Outputs a `<meta>` tag with the CSRF token. Place in the `<head>` section for JavaScript-initiated requests.

```ecr
<head>
  <%= csrf_metatag %>
</head>
```

### csrf_token

Returns the raw CSRF token string. Useful when you need the token value directly (e.g., for custom headers in JavaScript).

```ecr
<script>
  window.csrfToken = "<%= csrf_token %>";
</script>
```

## Key Source Files

| File | Purpose |
|------|---------|
| `src/amber/controller/base.cr` | Controller base class, includes all helper modules |
| `src/amber/controller/helpers/render.cr` | `render` macro, `LAYOUT` constant, template resolution |
| `src/amber/controller/helpers/tag_helpers.cr` | `tag`, `content_tag`, attribute handling |
| `src/amber/controller/helpers/form_helpers.cr` | `form_for`, input fields, select, checkbox, radio, label, submit |
| `src/amber/controller/helpers/text_helpers.cr` | `truncate`, `pluralize`, `highlight`, `simple_format`, `word_wrap`, `strip_tags`, `escape_html` |
| `src/amber/controller/helpers/number_helpers.cr` | `number_with_delimiter`, `number_to_currency`, `number_to_percentage`, `number_to_human_size` |
| `src/amber/controller/helpers/url_helpers.cr` | `link_to`, `button_to`, `mail_to`, `link_back` |
| `src/amber/controller/helpers/asset_helpers.cr` | `image_tag`, `stylesheet_link_tag`, `javascript_include_tag`, `favicon_tag` |
| `src/amber/controller/helpers/markdown.cr` | `render_markdown` (string and file) |
| `src/amber/controller/helpers/csrf.cr` | `csrf_token`, `csrf_tag`, `csrf_metatag` |
| `src/amber/markdown/options.cr` | `Amber::Markdown::Options` configuration struct |
