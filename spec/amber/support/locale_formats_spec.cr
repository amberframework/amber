require "../../spec_helper"

# The en-US and vi-VN patterns lost their lookaheads; these pin what the
# lookahead versions accepted (Amber 2.0.0-beta.9).
describe Amber::Support::LocaleFormat do
  describe "PHONE_FORMAT en-US" do
    pattern = Amber::Support::LocaleFormat::PHONE_FORMAT["en-US"]

    it "accepts numbers whose exchange is not followed by 11" do
      "2125551234".matches?(pattern).should be_true
      "+12125551234".matches?(pattern).should be_true
      "2125101234".matches?(pattern).should be_true
      "2125011234".matches?(pattern).should be_true
    end

    it "rejects a line number that starts with 11 after the exchange digit" do
      "2125111234".matches?(pattern).should be_false
      "+12125111234".matches?(pattern).should be_false
    end

    it "keeps accepting other Unicode decimal digits where it did" do
      "2125٥٥1234".matches?(pattern).should be_true
      # Only the ASCII digits 11 were excluded.
      "2125١١1234".matches?(pattern).should be_true
    end
  end

  describe "PHONE_FORMAT vi-VN" do
    pattern = Amber::Support::LocaleFormat::PHONE_FORMAT["vi-VN"]

    it "accepts 9x mobile prefixes other than 95" do
      "0901234567".matches?(pattern).should be_true
      "+84981234567".matches?(pattern).should be_true
    end

    it "rejects the 95 prefix" do
      "0951234567".matches?(pattern).should be_false
    end

    it "keeps its capture groups in the same places" do
      match = "+84981234567".match(pattern)
      match.should_not be_nil
      if match
        match[7]?.should eq "98"
        match[9]?.should eq "1234567"
      end
    end
  end
end
