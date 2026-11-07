require "../../../spec_helper"

private def sanitize(text : String, option : Amber::Schema::Parser::Sanitizer::Option) : String
  Amber::Schema::Parser::Sanitizer.new([option]).parse(JSON::Any.new(text)).as_s
end

module Amber::Schema::Parser
  describe Sanitizer do
    describe "RemoveNonPrintable" do
      it "keeps only space through ~" do
        sanitize("café \u007F~ \t", Sanitizer::Option::RemoveNonPrintable).should eq "caf ~ "
        sanitize("😀x\u0000", Sanitizer::Option::RemoveNonPrintable).should eq "x"
      end
    end

    describe "NormalizeWhitespace" do
      it "collapses every whitespace run, Unicode included, to one space and trims" do
        sanitize("\t a \n b \u0085c 　", Sanitizer::Option::NormalizeWhitespace).should eq "a b c"
      end

      it "leaves zero-width characters alone" do
        sanitize("a​b", Sanitizer::Option::NormalizeWhitespace).should eq "a​b"
      end

      it "returns an empty string for whitespace only" do
        sanitize("   ", Sanitizer::Option::NormalizeWhitespace).should eq ""
        sanitize("", Sanitizer::Option::NormalizeWhitespace).should eq ""
      end
    end

    describe "RemoveHTML" do
      it "removes tags and keeps a < with no > after it" do
        sanitize("<b>bold</b> a < b", Sanitizer::Option::RemoveHTML).should eq "bold a < b"
      end
    end
  end
end
