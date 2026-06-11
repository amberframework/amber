require "spec"
require "../../../src/amber/markdown"

describe Amber::Markdown::Options do
  describe "#base_url" do
    it "it disabled by default" do
      options = Amber::Markdown::Options.new
      Amber::Markdown.to_html("[foo](bar)", options).should eq %(<p><a href="bar">foo</a></p>\n)
      Amber::Markdown.to_html("![](bar)", options).should eq %(<p><img src="bar" alt="" /></p>\n)
    end

    it "absolutizes relative urls" do
      options = Amber::Markdown::Options.new
      options.base_url = URI.parse("http://example.com")
      Amber::Markdown.to_html("[foo](bar)", options).should eq %(<p><a href="http://example.com/bar">foo</a></p>\n)
      Amber::Markdown.to_html("[foo](https://example.com/baz)", options).should eq %(<p><a href="https://example.com/baz">foo</a></p>\n)
      Amber::Markdown.to_html("![](bar)", options).should eq %(<p><img src="http://example.com/bar" alt="" /></p>\n)
      Amber::Markdown.to_html("![](https://example.com/baz)", options).should eq %(<p><img src="https://example.com/baz" alt="" /></p>\n)
    end
  end
end
