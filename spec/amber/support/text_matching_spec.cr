require "../../spec_helper"

# Each expectation here is what the PCRE2 class or pattern this module
# replaced (`\w`, `\s`, `/i`, `<[^>]*>`) matched under Crystal's default
# Regex options.
module Amber::Support
  describe TextMatching do
    describe ".word_character?" do
      it "accepts letters, numbers and connector punctuation in any script" do
        {'a', 'Z', '9', '_', 'é', '日', '٣', '‿', '＿'}.each do |char|
          TextMatching.word_character?(char).should be_true
        end
      end

      it "accepts a non-spacing combining mark" do
        TextMatching.word_character?('́').should be_true
      end

      it "rejects punctuation, symbols and whitespace" do
        {'-', '.', ' ', '\t', '$', '€', ' '}.each do |char|
          TextMatching.word_character?(char).should be_false
        end
      end
    end

    describe ".whitespace?" do
      it "accepts ASCII and Unicode whitespace, NEL and the Mongolian vowel separator" do
        {' ', '\t', '\n', '\r', '\v', '\f', '\u0085', ' ', ' ', '᠎', ' ', '　'}.each do |char|
          TextMatching.whitespace?(char).should be_true
        end
      end

      it "rejects zero-width characters" do
        {'​', '﻿', 'a'}.each do |char|
          TextMatching.whitespace?(char).should be_false
        end
      end
    end

    describe ".same_ignoring_case?" do
      it "matches letters by simple case folding" do
        TextMatching.same_ignoring_case?('a', 'A').should be_true
        TextMatching.same_ignoring_case?('ſ', 'S').should be_true
        TextMatching.same_ignoring_case?('K', 'k').should be_true
        TextMatching.same_ignoring_case?('ẞ', 'ß').should be_true
        TextMatching.same_ignoring_case?('Σ', 'ς').should be_true
      end

      it "keeps the dotted capital I apart from i and I" do
        TextMatching.same_ignoring_case?('İ', 'i').should be_false
        TextMatching.same_ignoring_case?('İ', 'I').should be_false
        TextMatching.same_ignoring_case?('İ', 'İ').should be_true
      end

      it "does not match different letters" do
        TextMatching.same_ignoring_case?('a', 'b').should be_false
      end
    end

    describe ".match_starts_ignoring_case" do
      it "returns non-overlapping starts, leftmost first" do
        TextMatching.match_starts_ignoring_case("aaaa".chars, "aa".chars).should eq [0, 2]
        TextMatching.match_starts_ignoring_case("abABab".chars, "ab".chars).should eq [0, 2, 4]
        TextMatching.match_starts_ignoring_case("aaab".chars, "aab".chars).should eq [1]
        TextMatching.match_starts_ignoring_case("ab".chars, "abc".chars).should eq [] of Int32
      end
    end

    describe ".ends_with_ignoring_case?" do
      it "compares the last characters ignoring case" do
        TextMatching.ends_with_ignoring_case?("BoXES", "xes").should be_true
        TextMatching.ends_with_ignoring_case?("café", "FÉ").should be_true
        TextMatching.ends_with_ignoring_case?("es", "xes").should be_false
        TextMatching.ends_with_ignoring_case?("", "").should be_true
      end
    end

    describe ".starts_with_ignoring_case?" do
      it "compares the first characters ignoring case" do
        TextMatching.starts_with_ignoring_case?("HTTPS://x", "https:").should be_true
        TextMatching.starts_with_ignoring_case?("htt", "http:").should be_false
      end
    end

    describe ".remove_tags" do
      it "removes each span from a < to the next >" do
        TextMatching.remove_tags("<p>Hello <b>World</b></p>").should eq "Hello World"
        TextMatching.remove_tags("<<b>>").should eq ">"
        TextMatching.remove_tags("x<\n>y").should eq "xy"
      end

      it "keeps a < that no > follows" do
        TextMatching.remove_tags("a < b").should eq "a < b"
        TextMatching.remove_tags("<b>a <c").should eq "a <c"
      end

      it "keeps text with no tags and multibyte text around tags" do
        TextMatching.remove_tags("plain").should eq "plain"
        TextMatching.remove_tags("é<i>ü</i>😀").should eq "éü😀"
      end
    end
  end
end
