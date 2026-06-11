require "spec"
require "../../../src/amber/markdown"

describe "Table of Contents Generation" do
  describe "Amber::Markdown.to_html_with_toc" do
    it "returns html and toc as a named tuple" do
      result = Amber::Markdown.to_html_with_toc("# Hello")
      result[:html].should contain("<h1>Hello</h1>")
      result[:toc].should be_a(String)
    end

    it "generates a toc with heading entries" do
      markdown = "# Heading 1\n\nSome text.\n\n## Heading 2\n\nMore text.\n\n### Heading 3"
      result = Amber::Markdown.to_html_with_toc(markdown)

      result[:toc].should contain(%(<ul class="toc">))
      result[:toc].should contain(%(toc-level-1))
      result[:toc].should contain(%(toc-level-2))
      result[:toc].should contain(%(toc-level-3))
      result[:toc].should contain(%(Heading 1))
      result[:toc].should contain(%(Heading 2))
      result[:toc].should contain(%(Heading 3))
    end

    it "generates anchor links in toc entries" do
      result = Amber::Markdown.to_html_with_toc("# Hello\n\n## World")
      result[:toc].should contain(%(href="#anchor-))
      result[:toc].should contain(%(Hello))
      result[:toc].should contain(%(World))
    end

    it "returns empty toc when there are no headings" do
      result = Amber::Markdown.to_html_with_toc("Just a paragraph.")
      result[:html].should contain("<p>Just a paragraph.</p>")
      result[:toc].should eq("")
    end

    it "returns empty html and toc for empty source" do
      result = Amber::Markdown.to_html_with_toc("")
      result[:html].should eq("")
      result[:toc].should eq("")
    end

    it "renders the HTML correctly alongside toc generation" do
      markdown = "# Title\n\nParagraph text.\n\n## Subtitle"
      result = Amber::Markdown.to_html_with_toc(markdown)

      result[:html].should contain("<h1>Title</h1>")
      result[:html].should contain("<p>Paragraph text.</p>")
      result[:html].should contain("<h2>Subtitle</h2>")
    end

    it "includes all heading levels in the toc" do
      markdown = "# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6"
      result = Amber::Markdown.to_html_with_toc(markdown)

      result[:toc].should contain(%(toc-level-1))
      result[:toc].should contain(%(toc-level-2))
      result[:toc].should contain(%(toc-level-3))
      result[:toc].should contain(%(toc-level-4))
      result[:toc].should contain(%(toc-level-5))
      result[:toc].should contain(%(toc-level-6))
    end
  end

  describe "toc option in Options" do
    it "generates anchor IDs in headings when toc is true" do
      options = Amber::Markdown::Options.new(toc: true)
      result = Amber::Markdown.to_html("# Hello", options)
      result.should contain(%(id="anchor-))
      result.should contain(%(class="anchor"))
    end
  end
end
