require "./../../spec_helper"

module Amber::Pipe
  describe Pipeline do
    it "connects pipes to the pipeline for given valve" do
      pipeline = Pipeline.new

      pipeline.pipe_through :api do |valve|
        connect Pipe::Logger.instance, valve
        connect Pipe::Logger.instance, valve
      end

      pipeline.pipespipes.size.should eq 2

    end
  end
end
