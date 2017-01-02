require "./spec_helper"

describe Kemalyst::Generator do

  context "Init command" do

    it "should create the new project" do
      Kemalyst::Generator::MainCommand.run %w(init app ../testing/testapp)
      Dir.exists?("../testing/testapp").should be_true
    end

  end

end
