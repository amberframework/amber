require "spec"
require "../../../src/amber/markdown"

describe "Bare URL Autolinks" do
  it "converts a bare https URL to a link" do
    result = Amber::Markdown.to_html("Visit https://example.com today")
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
  end

  it "converts a bare http URL to a link" do
    result = Amber::Markdown.to_html("Visit http://example.com today")
    result.should contain(%(<a href="http://example.com">http://example.com</a>))
  end

  it "converts a www URL to a link with http scheme" do
    result = Amber::Markdown.to_html("Visit www.example.com today")
    result.should contain(%(<a href="http://www.example.com">www.example.com</a>))
  end

  it "converts a URL at the start of a line" do
    result = Amber::Markdown.to_html("https://example.com is a site")
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
  end

  it "converts a URL with a path" do
    result = Amber::Markdown.to_html("See https://example.com/path/to/page for details")
    result.should contain(%(<a href="https://example.com/path/to/page">https://example.com/path/to/page</a>))
  end

  it "converts a URL with query parameters" do
    result = Amber::Markdown.to_html("Go to https://example.com/search?q=test&page=1 now")
    result.should contain("https://example.com/search?q=test&amp;page=1")
  end

  it "converts multiple bare URLs in the same line" do
    result = Amber::Markdown.to_html("Visit https://one.com and https://two.com today")
    result.should contain(%(<a href="https://one.com">https://one.com</a>))
    result.should contain(%(<a href="https://two.com">https://two.com</a>))
  end

  it "does not convert URLs inside angle bracket autolinks" do
    result = Amber::Markdown.to_html("<https://example.com>")
    # Angle bracket autolinks are handled by the existing auto_link method
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
  end

  it "does not convert URLs inside explicit markdown links" do
    result = Amber::Markdown.to_html("[link](https://example.com)")
    result.should contain(%(<a href="https://example.com">link</a>))
    # Should not have double-wrapped the URL
    result.scan(/<a /).size.should eq(1)
  end

  it "handles trailing punctuation correctly" do
    result = Amber::Markdown.to_html("Visit https://example.com.")
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
    result.should contain(".")
  end

  it "handles URL followed by comma" do
    result = Amber::Markdown.to_html("See https://example.com, for info")
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
  end

  it "converts a URL on its own line" do
    result = Amber::Markdown.to_html("https://example.com")
    result.should contain(%(<a href="https://example.com">https://example.com</a>))
  end
end
