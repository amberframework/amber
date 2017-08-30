require "../../../spec_helper"

module Amber::Extensions
  describe NumberExtension do
    it "negative number test" do
      (-5.5423).negative?.should eq(true)
    end

    it "positive number test" do
      (17).positive?.should eq(true)
    end

    it "returns true when number is 0" do
      (0).zero?.should eq(true)
      (10/5 - 2).zero?.should eq(true)
    end

    it "returns true when number is divisable by X" do
      (10).div?(5).should eq(true)
    end

    it "returns true when X above Number" do
      10.above?(5).should eq(true)
      17.above?(21).should eq(false)
    end

    it "returns true when X below Number" do
      100.below?(200).should eq(true)
      50.below?(25).should eq(false)
    end
  end
end
