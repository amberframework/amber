require "../../spec_helper"

# Expected values are what the lookaround patterns (Amber 2.0.0-beta.9)
# matched: CODE_FENCE /^`{3,}(?!.*`)|^~{3,}/ and CLOSING_CODE_FENCE
# /^(?:`{3,}|~{3,})(?= *$)/.
describe Amber::Markdown::Rule::CodeBlock do
  describe ".opening_fence_length" do
    it "measures a backtick fence with no backtick after it" do
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("```").should eq 3
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("`````ruby").should eq 5
    end

    it "rejects a backtick fence with a backtick later on the line" do
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("``` a`b").should be_nil
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("````").should eq 4
    end

    it "measures a tilde fence whatever follows" do
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("~~~ `x`").should eq 3
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("~~~~").should eq 4
    end

    it "rejects runs shorter than three and other characters" do
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("``").should be_nil
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("~~").should be_nil
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("").should be_nil
      Amber::Markdown::Rule::CodeBlock.opening_fence_length(" ```").should be_nil
    end

    it "looks for a later backtick only up to a newline" do
      Amber::Markdown::Rule::CodeBlock.opening_fence_length("```a\n`").should eq 3
    end
  end

  describe ".closing_fence_length" do
    it "measures a fence followed by nothing but spaces" do
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("```").should eq 3
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("~~~~   ").should eq 4
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("``` \n").should eq 3
    end

    it "rejects a fence followed by anything but spaces" do
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("``` x").should be_nil
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("```\t").should be_nil
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("```\n\n").should be_nil
      Amber::Markdown::Rule::CodeBlock.closing_fence_length("``").should be_nil
    end
  end

  describe "rendering" do
    it "closes a fence only with a run at least as long as the opening one" do
      Amber::Markdown.to_html("````\ncode\n```\n````\n").should eq "<pre><code>code\n```\n</code></pre>\n"
    end

    it "does not open a fence whose info string holds a backtick" do
      Amber::Markdown.to_html("``` a`b\n").should eq "<p>``` a`b</p>\n"
    end
  end
end
