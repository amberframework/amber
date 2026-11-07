require "../../../spec_helper"

module Amber::Controller::Helpers
  describe TextHelpers do
    controller = build_controller

    describe "#truncate" do
      it "truncates text longer than the limit" do
        controller.truncate("Hello World", length: 8).should eq "Hello..."
      end

      it "returns the original text when shorter than the limit" do
        controller.truncate("Hi", length: 10).should eq "Hi"
      end

      it "returns the original text when exactly the limit" do
        controller.truncate("Hello", length: 5).should eq "Hello"
      end

      it "uses a custom omission string" do
        controller.truncate("Hello World", length: 8, omission: ">>").should eq "Hello >>"
      end

      it "handles edge case when omission is longer than length" do
        controller.truncate("Hello", length: 2, omission: "...").should eq "..."
      end

      it "uses default length of 30" do
        text = "a" * 35
        result = controller.truncate(text)
        result.size.should eq 30
        result.should end_with "..."
      end

      it "handles empty string" do
        controller.truncate("", length: 5).should eq ""
      end
    end

    describe "#pluralize" do
      it "returns singular form for count of 1" do
        controller.pluralize(1, "person").should eq "1 person"
      end

      it "returns simple plural for count of 2" do
        controller.pluralize(2, "item").should eq "2 items"
      end

      it "returns simple plural for count of 0" do
        controller.pluralize(0, "item").should eq "0 items"
      end

      it "uses a custom plural when provided" do
        controller.pluralize(2, "person", "people").should eq "2 people"
      end

      it "uses singular for exactly 1 even with custom plural" do
        controller.pluralize(1, "person", "people").should eq "1 person"
      end

      it "handles negative counts" do
        controller.pluralize(-1, "item").should eq "-1 items"
      end
    end

    describe "#highlight" do
      it "wraps the phrase with a mark tag" do
        controller.highlight("Hello World", "World").should eq "Hello <mark>World</mark>"
      end

      it "is case insensitive" do
        controller.highlight("Hello World", "world").should eq "Hello <mark>World</mark>"
      end

      it "uses a custom tag" do
        controller.highlight("Hello World", "World", tag: "em").should eq "Hello <em>World</em>"
      end

      it "highlights multiple occurrences" do
        controller.highlight("foo bar foo", "foo").should eq "<mark>foo</mark> bar <mark>foo</mark>"
      end

      it "returns text unchanged when phrase is not found" do
        controller.highlight("Hello World", "xyz").should eq "Hello World"
      end

      it "escapes HTML in the source text" do
        result = controller.highlight("<b>Hello</b> World", "World")
        result.should contain "&lt;b&gt;"
        result.should contain "<mark>World</mark>"
      end
    end

    describe "#simple_format" do
      it "wraps text in a paragraph tag" do
        controller.simple_format("Hello").should eq "<p>Hello</p>"
      end

      it "converts single newlines to br tags" do
        controller.simple_format("Hello\nWorld").should eq "<p>Hello<br />World</p>"
      end

      it "splits double newlines into separate paragraphs" do
        controller.simple_format("Para1\n\nPara2").should eq "<p>Para1</p><p>Para2</p>"
      end

      it "escapes HTML in the text" do
        controller.simple_format("<script>alert('xss')</script>").should contain "&lt;script&gt;"
      end

      it "handles empty string" do
        controller.simple_format("").should eq "<p></p>"
      end
    end

    describe "#word_wrap" do
      it "wraps text at the specified width" do
        result = controller.word_wrap("The quick brown fox jumps over the lazy dog", line_width: 15)
        result.should contain "\n"
      end

      it "does not wrap text shorter than the width" do
        controller.word_wrap("Short text", line_width: 80).should eq "Short text"
      end

      it "uses default width of 80" do
        short_text = "Hello World"
        controller.word_wrap(short_text).should eq short_text
      end
    end

    describe "#strip_tags" do
      it "strips simple HTML tags" do
        controller.strip_tags("<p>Hello</p>").should eq "Hello"
      end

      it "strips nested tags" do
        controller.strip_tags("<div><p>Hello <b>World</b></p></div>").should eq "Hello World"
      end

      it "strips self-closing tags" do
        controller.strip_tags("Hello<br />World").should eq "HelloWorld"
      end

      it "handles malformed HTML" do
        controller.strip_tags("<p>Unclosed paragraph").should eq "Unclosed paragraph"
      end

      it "returns text without tags unchanged" do
        controller.strip_tags("No tags here").should eq "No tags here"
      end

      it "handles empty string" do
        controller.strip_tags("").should eq ""
      end

      it "strips script tags" do
        controller.strip_tags("<script>alert('xss')</script>").should eq "alert('xss')"
      end
    end

    describe "#escape_html" do
      it "escapes angle brackets" do
        controller.escape_html("<div>").should contain "&lt;"
        controller.escape_html("<div>").should contain "&gt;"
      end

      it "escapes ampersands" do
        controller.escape_html("a & b").should contain "&amp;"
      end

      it "escapes quotes" do
        controller.escape_html("a \"b\" c").should contain "&quot;"
      end

      it "escapes single quotes" do
        controller.escape_html("it's").should contain "&#39;"
      end

      it "handles empty string" do
        controller.escape_html("").should eq ""
      end

      it "handles text with no special characters" do
        controller.escape_html("plain text").should eq "plain text"
      end
    end

    # Expected values below are what the Regex implementations (Amber
    # 2.0.0-beta.9) returned for the same input.
    describe "#highlight, edge cases" do
      it "matches case-insensitively by simple case folding" do
        controller.highlight("Ruſt rust RUST", "rust").should eq "<mark>Ruſt</mark> <mark>rust</mark> <mark>RUST</mark>"
      end

      it "compares character by character, so ß does not match SS" do
        controller.highlight("Straße STRASSE", "ß").should eq "Stra<mark>ß</mark>e STRASSE"
      end

      it "does not match a dotted capital I for i" do
        controller.highlight("İstanbul istanbul", "i").should eq "İstanbul <mark>i</mark>stanbul"
      end

      it "finds a match that starts inside a failed partial match" do
        controller.highlight("aaab AAAB", "aab").should eq "a<mark>aab</mark> A<mark>AAB</mark>"
      end

      it "does not overlap matches" do
        controller.highlight("aaa", "aa").should eq "<mark>aa</mark>a"
      end

      it "marks the empty text around every character for an empty phrase" do
        controller.highlight("ab", "").should eq "<mark></mark>a<mark></mark>b<mark></mark>"
      end

      it "matches an escaped phrase against the escaped text" do
        controller.highlight("Tom & Jerry", "&").should eq "Tom <mark>&amp;</mark> Jerry"
        controller.highlight("x<y", "<").should eq "x<mark>&lt;</mark>y"
      end
    end

    describe "#simple_format, edge cases" do
      it "treats three or more newlines as one paragraph break" do
        controller.simple_format("a\n\n\nb").should eq "<p>a</p><p>b</p>"
      end

      it "keeps an empty paragraph before a leading break and after a trailing one" do
        controller.simple_format("\n\na").should eq "<p></p><p>a</p>"
        controller.simple_format("a\n\n").should eq "<p>a</p><p></p>"
      end

      it "does not count carriage returns toward a paragraph break" do
        controller.simple_format("a\r\n\r\nb").should eq "<p>a\r<br />\r<br />b</p>"
      end

      it "keeps single newlines inside a paragraph" do
        controller.simple_format("a\nb\n\nc").should eq "<p>a<br />b</p><p>c</p>"
      end
    end

    describe "#word_wrap, edge cases" do
      it "breaks at the last whitespace that fits" do
        controller.word_wrap("The quick brown fox", line_width: 10).should eq "The quick\nbrown fox"
      end

      it "leaves a word longer than the width whole when no break fits" do
        controller.word_wrap("abcdefghij klm", line_width: 4).should eq "abcdefghij\nklm"
      end

      it "turns each whitespace run into one newline" do
        controller.word_wrap("one  two\tthree", line_width: 3).should eq "one\ntwo\nthree"
      end

      it "keeps existing newlines" do
        controller.word_wrap("line one\nline two", line_width: 20).should eq "line one\nline two"
      end

      it "breaks at Unicode whitespace" do
        controller.word_wrap("a b c", line_width: 1).should eq "a\nb\nc"
        controller.word_wrap("a　b", line_width: 1).should eq "a\nb"
      end

      it "drops trailing whitespace" do
        controller.word_wrap("word ", line_width: 4).should eq "word"
      end

      it "keeps leading whitespace that starts no line" do
        controller.word_wrap(" lead", line_width: 3).should eq " lead"
      end

      it "raises for a width below 1" do
        expect_raises(ArgumentError) { controller.word_wrap("aa bb", line_width: 0) }
      end
    end

    describe "#strip_tags, edge cases" do
      it "keeps a < with no > after it" do
        controller.strip_tags("a < b").should eq "a < b"
        controller.strip_tags("a <b c").should eq "a <b c"
      end

      it "removes from a < to the first >" do
        controller.strip_tags("<<b>>").should eq ">"
        controller.strip_tags("<>").should eq ""
      end

      it "removes tags that span lines" do
        controller.strip_tags("x<\n>y").should eq "xy"
      end
    end
  end
end
