require "spec"
require "../../../src/amber/markdown"

describe "Syntax Highlighting Hooks" do
  it "uses default rendering when no code_highlighter is set" do
    result = Amber::Markdown.to_html("```ruby\nputs 'hello'\n```")
    result.should contain("<pre>")
    result.should contain(%(<code class="language-ruby">))
    result.should contain("puts 'hello'")
    result.should contain("</code>")
    result.should contain("</pre>")
  end

  it "calls the code_highlighter callback for fenced code blocks" do
    highlighter = ->(code : String, language : String) {
      %(<div class="highlight"><pre class="#{language}">#{code}</pre></div>)
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    result = Amber::Markdown.to_html("```ruby\nputs 'hello'\n```", options)
    result.should contain(%(<div class="highlight">))
    result.should contain(%(<pre class="ruby">))
    result.should contain("puts 'hello'")
    result.should_not contain(%(<code class="language-ruby">))
  end

  it "passes the correct language to the highlighter" do
    captured_language = ""
    highlighter = ->(code : String, language : String) {
      captured_language = language
      "<pre>#{code}</pre>"
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    Amber::Markdown.to_html("```javascript\nconsole.log('hi')\n```", options)
    captured_language.should eq("javascript")
  end

  it "passes the correct code content to the highlighter" do
    captured_code = ""
    highlighter = ->(code : String, language : String) {
      captured_code = code
      "<pre>#{code}</pre>"
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    Amber::Markdown.to_html("```\nline1\nline2\n```", options)
    captured_code.should eq("line1\nline2\n")
  end

  it "passes empty string as language when no language is specified" do
    captured_language = "not_set"
    highlighter = ->(code : String, language : String) {
      captured_language = language
      "<pre>#{code}</pre>"
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    Amber::Markdown.to_html("```\nsome code\n```", options)
    captured_language.should eq("")
  end

  it "does not affect inline code rendering" do
    call_count = 0
    highlighter = ->(code : String, language : String) {
      call_count += 1
      "<pre>#{code}</pre>"
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    result = Amber::Markdown.to_html("Use `inline code` here", options)
    result.should contain("<code>inline code</code>")
    call_count.should eq(0)
  end

  it "uses the highlighter output as raw HTML" do
    highlighter = ->(code : String, language : String) {
      %(<pre><code><span class="keyword">def</span></code></pre>)
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    result = Amber::Markdown.to_html("```crystal\ndef foo\n```", options)
    result.should contain(%(<span class="keyword">def</span>))
  end

  it "handles multiple code blocks with highlighter" do
    call_count = 0
    highlighter = ->(code : String, language : String) {
      call_count += 1
      %(<div class="block-#{call_count}">#{code}</div>)
    }

    options = Amber::Markdown::Options.new
    options.code_highlighter = highlighter

    markdown = "```ruby\nruby code\n```\n\nSome text.\n\n```python\npython code\n```"
    result = Amber::Markdown.to_html(markdown, options)
    call_count.should eq(2)
    result.should contain(%(<div class="block-1">))
    result.should contain(%(<div class="block-2">))
  end
end
