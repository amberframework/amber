require "../../../../spec_helper"

module Amber
  module Pipe
    describe Pipeline do
      it "connects pipes to the pipeline for given valve" do
        pipeline = Pipeline.instance

        pipeline.build :api do
          plug Pipe::Logger.instance
          plug Pipe::Error.instance
        end
        # Should eq 3 because of default pipe
        pipeline.pipeline[:api].size.should eq 2
      end
    end
  end
end
