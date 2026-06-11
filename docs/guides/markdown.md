# Markdown

Amber V2 includes an internalized Markdown renderer (`Amber::Markdown`) that converts Markdown source to HTML. It supports GitHub Flavored Markdown (GFM) extensions, table of contents generation, footnotes, and pluggable syntax highlighting for fenced code blocks. No external shards are required.

## Quick Start

```crystal
require "amber/markdown"

html = Amber::Markdown.to_html("# Hello World")
# => "<h1>Hello World</h1>\n"
```

## API

### to_html

Converts a Markdown string to HTML:

```crystal
Amber::Markdown.to_html(source : String, options = Options.new) : String
```

Returns an empty string when given an empty source.

```crystal
Amber::Markdown.to_html("")
# => ""

Amber::Markdown.to_html("**Bold** and *italic*")
# => "<p><strong>Bold</strong> and <em>italic</em></p>\n"
```

### to_html_with_toc

Converts Markdown to HTML and generates a table of contents from headings:

```crystal
Amber::Markdown.to_html_with_toc(source : String, options = Options.new) : {html: String, toc: String}
```

Returns a named tuple with `:html` and `:toc` keys. The `:toc` value is an HTML string containing a `<ul>` list of headings with anchor links.

```crystal
markdown = "# Title\n\nSome text.\n\n## Subtitle\n\nMore text."
result = Amber::Markdown.to_html_with_toc(markdown)

result[:html]  # => HTML with <h1>, <h2> tags and anchor elements
result[:toc]   # => '<ul class="toc">\n<li class="toc-level-1"><a href="#anchor-Title">Title</a></li>\n...'
```

The TOC includes all heading levels (h1 through h6). Each entry has a CSS class `toc-level-N` where N is the heading level, making it easy to style nested navigation.

When there are no headings, the `:toc` value is an empty string.

## Options

The `Amber::Markdown::Options` class controls rendering behavior:

```crystal
options = Amber::Markdown::Options.new(
  gfm: false,          # Enable GFM extensions (tables, strikethrough, task lists, autolinks)
  toc: false,          # Generate anchor links in headings for TOC
  smart: false,        # Convert quotes, dashes, and ellipses to typographic equivalents
  source_pos: false,   # Add data-sourcepos attributes to block elements
  safe: false,         # Strip raw HTML (replaced with comments)
  prettyprint: false,  # Add prettyprint class to <pre> tags for Google code-prettify
  base_url: nil,       # URI for resolving relative links
  code_highlighter: nil # Custom syntax highlighting callback
)
```

### Option Details

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gfm` | `Bool` | `false` | Enables GFM extensions: tables, strikethrough, task lists, bare URL autolinks |
| `toc` | `Bool` | `false` | Generates anchor `<a>` elements inside headings for linking from a TOC |
| `smart` | `Bool` | `false` | Converts `--` to en dash, `---` to em dash, `...` to ellipsis, straight quotes to curly |
| `source_pos` | `Bool` | `false` | Adds `data-source-pos` attributes to block-level elements |
| `safe` | `Bool` | `false` | Replaces raw HTML blocks and inline HTML with `<!-- raw HTML omitted -->` |
| `prettyprint` | `Bool` | `false` | Adds `class="prettyprint"` to `<pre>` tags for Google code-prettify |
| `base_url` | `URI?` | `nil` | Base URI for resolving relative link destinations |
| `code_highlighter` | `Proc?` | `nil` | Custom callback for fenced code block syntax highlighting |

## GFM Extensions

When `gfm: true` is set, the following GitHub Flavored Markdown extensions are enabled.

### Tables

Pipe-delimited tables with optional column alignment:

```markdown
| Left | Center | Right | Default |
| :--- | :---:  | ---:  | ---     |
| a    | b      | c     | d       |
```

Renders as an HTML `<table>` with `<thead>`, `<tbody>`, `<th>`, and `<td>` elements. Column alignment is applied via `style="text-align: ..."` attributes.

Tables support inline formatting (bold, italic, code, links) within cells, escaped pipes (`\|`), and optional leading/trailing pipes. Mismatched column counts are handled by padding with empty cells or truncating extra columns.

### Strikethrough

Double tildes wrap text in `<del>` tags:

```markdown
~~deleted text~~
```

Renders as `<del>deleted text</del>`. Single tildes are not treated as strikethrough. Strikethrough can contain other inline formatting such as bold, italic, and code.

### Task Lists

Checkbox list items using `[ ]` and `[x]` (or `[X]`) syntax:

```markdown
- [x] Completed task
- [ ] Pending task
- Regular list item
```

Renders checked items with `<input type="checkbox" disabled="" checked="" />` and unchecked items with `<input type="checkbox" disabled="" />`. Task lists support nested lists and inline formatting.

### Bare URL Autolinks

Bare URLs starting with `https://`, `http://`, or `www.` are automatically converted to clickable links:

```markdown
Visit https://example.com for details.
Check www.example.com too.
```

Renders as `<a href="https://example.com">https://example.com</a>`. URLs with paths, query parameters, and fragments are supported. Trailing punctuation (periods, commas) is excluded from the link.

## Footnotes

Footnotes are supported regardless of the `gfm` setting:

```markdown
Text with a footnote[^1].

[^1]: This is the footnote content.
```

References render as superscript links (`<sup class="footnote-ref">`), and definitions are collected into a `<section class="footnotes">` at the end of the document with back-reference links.

Footnotes are numbered in the order they are first referenced, not in the order they are defined. Text labels (e.g., `[^note]`) are supported alongside numeric labels.

## Table of Contents

To generate a table of contents, use `to_html_with_toc`:

```crystal
markdown = "# Introduction\n\n## Setup\n\n## Usage\n\n### Advanced\n\n## FAQ"
result = Amber::Markdown.to_html_with_toc(markdown)

# result[:toc] contains:
# <ul class="toc">
# <li class="toc-level-1"><a href="#anchor-Introduction">Introduction</a></li>
# <li class="toc-level-2"><a href="#anchor-Setup">Setup</a></li>
# <li class="toc-level-2"><a href="#anchor-Usage">Usage</a></li>
# <li class="toc-level-3"><a href="#anchor-Advanced">Advanced</a></li>
# <li class="toc-level-2"><a href="#anchor-FAQ">FAQ</a></li>
# </ul>
```

If you only need anchor links in headings without a separate TOC HTML string, use the `toc` option with `to_html`:

```crystal
options = Amber::Markdown::Options.new(toc: true)
html = Amber::Markdown.to_html("# Hello", options)
# Headings will contain <a id="anchor-Hello" class="anchor" href="#anchor-Hello"></a>
```

## Syntax Highlighting

By default, fenced code blocks render as `<pre><code class="language-LANG">...</code></pre>`. You can provide a custom syntax highlighter callback to control the output.

### Default Rendering

```crystal
html = Amber::Markdown.to_html("```ruby\nputs 'hello'\n```")
# => <pre><code class="language-ruby">puts &#39;hello&#39;\n</code></pre>
```

### Custom Highlighter

Set the `code_highlighter` option to a `Proc(String, String, String)` that receives the code content and language, and returns highlighted HTML:

```crystal
highlighter = ->(code : String, language : String) {
  %(<div class="highlight"><pre class="#{language}">#{code}</pre></div>)
}

options = Amber::Markdown::Options.new
options.code_highlighter = highlighter

html = Amber::Markdown.to_html("```ruby\nputs 'hello'\n```", options)
# => <div class="highlight"><pre class="ruby">puts 'hello'\n</pre></div>
```

The highlighter is called once per fenced code block. It is not called for inline code spans. When no language is specified on the fence, an empty string is passed as the language argument.

## Safe Mode

When `safe: true`, raw HTML is stripped from the output:

```crystal
options = Amber::Markdown::Options.new(safe: true)
html = Amber::Markdown.to_html("<script>alert('xss')</script>", options)
# HTML blocks are replaced with: <!-- raw HTML omitted -->
```

Additionally, links and images with potentially unsafe protocols (e.g., `javascript:`) have their destinations removed.

## Base URL for Relative Links

Set `base_url` to resolve relative link destinations:

```crystal
options = Amber::Markdown::Options.new(base_url: URI.parse("https://example.com/docs/"))
html = Amber::Markdown.to_html("[Guide](getting-started.md)", options)
# Link href becomes "https://example.com/docs/getting-started.md"
```

Absolute URLs are left unchanged. Only relative URLs are resolved against the base URL.

## Prettyprint Mode

Enable Google code-prettify integration by adding the `prettyprint` class to `<pre>` tags:

```crystal
options = Amber::Markdown::Options.new(prettyprint: true)
html = Amber::Markdown.to_html("```\nsome code\n```", options)
# => <pre class="prettyprint"><code>some code\n</code></pre>
```

## Controller Helper

The `MarkdownHelper` module is included in `Amber::Controller::Base` automatically. It provides a convenient `markdown` helper for use in controllers and templates.

```crystal
class PagesController < ApplicationController
  def show
    @content = Amber::Markdown.to_html(raw_markdown)
    render("show.ecr")
  end
end
```

In an ECR template:

```ecr
<article>
  <%= Amber::Markdown.to_html(@raw_content) %>
</article>
```

For rendering with a table of contents sidebar:

```crystal
class DocsController < ApplicationController
  def show
    source = File.read("docs/#{params["page"]}.md")
    result = Amber::Markdown.to_html_with_toc(source)
    @toc = result[:toc]
    @content = result[:html]
    render("show.ecr")
  end
end
```

```ecr
<div class="docs-layout">
  <nav class="sidebar">
    <%= @toc %>
  </nav>
  <article>
    <%= @content %>
  </article>
</div>
```

## Source Files

- `src/amber/markdown.cr` -- Module entry point with `to_html` and `to_html_with_toc`
- `src/amber/markdown/options.cr` -- Options class with all rendering flags
- `src/amber/markdown/parser.cr` -- Parser module (delegates to block parser)
- `src/amber/markdown/parsers/block.cr` -- Block-level parser
- `src/amber/markdown/parsers/inline.cr` -- Inline-level parser
- `src/amber/markdown/renderer.cr` -- Abstract Renderer base class
- `src/amber/markdown/renderers/html_renderer.cr` -- HTMLRenderer with TOC, footnotes, and syntax highlighting
- `src/amber/markdown/node.cr` -- AST Node class
- `src/amber/markdown/rule.cr` -- Parsing rules base
- `src/amber/markdown/rules/` -- Block-level rules (heading, code_block, table, list, etc.)
- `src/amber/markdown/html_entities.cr` -- HTML entity decoding
- `src/amber/markdown/utils.cr` -- Utility functions
