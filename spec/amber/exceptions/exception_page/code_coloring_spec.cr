require "../../../spec_helper"

describe ExceptionPage::CodeColoring do
  it "colors keywords, constants, numbers, strings and comments" do
    html = ExceptionPage::CodeColoring.highlight(%(def run(name = "x") : Int32 1 # note))

    html.should contain(%(<span class="k">def</span>))
    html.should contain(%(<span class="s">&quot;x&quot;</span>))
    html.should contain(%(<span class="t">Int32</span>))
    html.should contain(%(<span class="n">1</span>))
    html.should contain(%(<span class="c"># note</span>))
  end

  it "escapes markup in every kind of piece" do
    html = ExceptionPage::CodeColoring.highlight(%(<script> "<b>" # <i>))

    html.should_not contain("<script>")
    html.should_not contain("<b>")
    html.should_not contain("<i>")
  end

  it "keeps a string with an escaped quote whole and handles an unclosed string" do
    ExceptionPage::CodeColoring.highlight(%q("a\"b" c)).should eq(%q(<span class="s">&quot;a\&quot;b&quot;</span> c))
    ExceptionPage::CodeColoring.highlight(%q("open)).should eq(%q(<span class="s">&quot;open</span>))
  end

  it "keeps multibyte text intact" do
    ExceptionPage::CodeColoring.highlight("é → ü").should contain("→")
  end
end
