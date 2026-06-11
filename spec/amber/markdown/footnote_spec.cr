require "spec"
require "../../../src/amber/markdown"

describe "Footnotes" do
  it "renders a footnote reference as a superscript link" do
    result = Amber::Markdown.to_html("Text with a footnote[^1].\n\n[^1]: This is the footnote.")
    result.should contain(%(<sup class="footnote-ref"><a href="#fn-1" id="fnref-1">1</a></sup>))
  end

  it "renders footnote definitions in a section at the end" do
    result = Amber::Markdown.to_html("Text[^1].\n\n[^1]: Footnote content.")
    result.should contain(%(<section class="footnotes">))
    result.should contain(%(<ol>))
    result.should contain(%(<li id="fn-1">))
    result.should contain("Footnote content.")
    result.should contain(%(<a href="#fnref-1">&#8617;</a>))
    result.should contain(%(</ol>))
    result.should contain(%(</section>))
  end

  it "numbers footnotes in order of first reference" do
    result = Amber::Markdown.to_html("First[^a] and second[^b].\n\n[^a]: Note A.\n\n[^b]: Note B.")
    result.should contain(%(<a href="#fn-a" id="fnref-a">1</a>))
    result.should contain(%(<a href="#fn-b" id="fnref-b">2</a>))
  end

  it "renders multiple footnote references" do
    markdown = "Paragraph one[^1].\n\nParagraph two[^2].\n\n[^1]: First note.\n\n[^2]: Second note."
    result = Amber::Markdown.to_html(markdown)
    result.should contain(%(<li id="fn-1">))
    result.should contain(%(<li id="fn-2">))
    result.should contain("First note.")
    result.should contain("Second note.")
  end

  it "handles footnotes with text labels" do
    result = Amber::Markdown.to_html("Text[^note].\n\n[^note]: A named footnote.")
    result.should contain(%(<sup class="footnote-ref"><a href="#fn-note" id="fnref-note">1</a></sup>))
    result.should contain(%(<li id="fn-note">))
    result.should contain("A named footnote.")
  end

  it "does not render footnotes section when there are no references" do
    result = Amber::Markdown.to_html("Just plain text.")
    result.should_not contain(%(<section class="footnotes">))
  end

  it "renders footnote reference inline in text" do
    result = Amber::Markdown.to_html("Hello[^1] world.\n\n[^1]: Greetings.")
    result.should contain("Hello")
    result.should contain(%(<sup class="footnote-ref">))
    result.should contain("world.")
  end

  it "handles footnote reference without definition gracefully" do
    result = Amber::Markdown.to_html("Text[^missing].")
    result.should contain(%(<sup class="footnote-ref"><a href="#fn-missing" id="fnref-missing">1</a></sup>))
    # Should still render the section but with empty content
    result.should contain(%(<section class="footnotes">))
  end
end
