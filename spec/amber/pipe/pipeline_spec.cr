require "http"
require "spec"
require "../../../spec_helper"

module Amber::Pipe
  describe Pipeline do
    it "connects pipes to the pipeline for given valve" do
      pipeline = Pipeline.instance

      pipeline.build :api do
        plug Pipe::Logger.instance
        plug Pipe::Logger.instance
      end

      pipeline.pipeline[:api].size.should eq 2
    end
  end
end
