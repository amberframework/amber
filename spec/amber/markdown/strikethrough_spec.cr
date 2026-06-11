require "spec"
require "../../../src/amber/markdown"

describe "Strikethrough" do
  it "renders basic strikethrough" do
    result = Amber::Markdown.to_html("~~deleted~~")
    result.should contain("<del>deleted</del>")
  end

  it "renders strikethrough within a paragraph" do
    result = Amber::Markdown.to_html("This is ~~deleted~~ text")
    result.should eq("<p>This is <del>deleted</del> text</p>\n")
  end

  it "renders strikethrough with inline formatting inside" do
    result = Amber::Markdown.to_html("~~**bold deleted**~~")
    result.should contain("<del><strong>bold deleted</strong></del>")
  end

  it "renders strikethrough with emphasis inside" do
    result = Amber::Markdown.to_html("~~*italic deleted*~~")
    result.should contain("<del><em>italic deleted</em></del>")
  end

  it "does not render single tilde as strikethrough" do
    result = Amber::Markdown.to_html("~not deleted~")
    result.should_not contain("<del>")
    result.should contain("~")
  end

  it "renders strikethrough in list items" do
    result = Amber::Markdown.to_html("- ~~item~~")
    result.should contain("<del>item</del>")
  end

  it "renders multiple strikethroughs in one line" do
    result = Amber::Markdown.to_html("~~one~~ and ~~two~~")
    result.should contain("<del>one</del>")
    result.should contain("<del>two</del>")
  end

  it "does not match unbalanced tildes" do
    result = Amber::Markdown.to_html("~~not closed")
    result.should_not contain("<del>")
  end

  it "renders strikethrough with code inside" do
    result = Amber::Markdown.to_html("~~`code`~~")
    result.should contain("<del><code>code</code></del>")
  end
end
