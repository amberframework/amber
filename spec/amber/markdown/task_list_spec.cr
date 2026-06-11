require "spec"
require "../../../src/amber/markdown"

describe "Task Lists" do
  it "renders unchecked task list item" do
    result = Amber::Markdown.to_html("- [ ] unchecked")
    result.should contain("<li><input type=\"checkbox\" disabled=\"\" /> unchecked</li>")
  end

  it "renders checked task list item with lowercase x" do
    result = Amber::Markdown.to_html("- [x] checked")
    result.should contain("<li><input type=\"checkbox\" disabled=\"\" checked=\"\" /> checked</li>")
  end

  it "renders checked task list item with uppercase X" do
    result = Amber::Markdown.to_html("- [X] checked")
    result.should contain("<li><input type=\"checkbox\" disabled=\"\" checked=\"\" /> checked</li>")
  end

  it "renders mixed task list" do
    markdown = "- [ ] todo\n- [x] done\n- [ ] another todo"
    result = Amber::Markdown.to_html(markdown)
    result.should contain("<input type=\"checkbox\" disabled=\"\" /> todo")
    result.should contain("<input type=\"checkbox\" disabled=\"\" checked=\"\" /> done")
    result.should contain("<input type=\"checkbox\" disabled=\"\" /> another todo")
  end

  it "renders regular list items without task markers" do
    result = Amber::Markdown.to_html("- regular item")
    result.should_not contain("<input")
    result.should contain("<li>regular item</li>")
  end

  it "does not treat brackets in middle of text as task" do
    result = Amber::Markdown.to_html("- some text [ ] more text")
    result.should_not contain("<input")
  end

  it "renders task list with inline formatting" do
    result = Amber::Markdown.to_html("- [x] **bold task**")
    result.should contain("<input type=\"checkbox\" disabled=\"\" checked=\"\"")
    result.should contain("<strong>bold task</strong>")
  end

  it "renders nested task lists" do
    markdown = "- [x] parent\n    - [ ] child"
    result = Amber::Markdown.to_html(markdown)
    result.should contain("checked")
    result.should contain("<input type=\"checkbox\" disabled=\"\" /> child")
  end
end
