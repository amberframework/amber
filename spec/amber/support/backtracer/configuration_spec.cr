require "./spec_helper"

describe Backtracer::Configuration do
  it "should set #src_path to current dir from default" do
    with_configuration do |configuration|
      configuration.src_path.should eq(Dir.current)
    end
  end
end
