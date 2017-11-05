require "../../../spec_helper"

module Amber
  server = Server.new
  module DSL
    describe Server do

      describe "pipeline" do
        context "generating a single ':custom' pipeline" do
          Amber::Server.configure do |app|
            pipeline :custom do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end
          end

          it "should add ':custom' to the server's pipeline" do
            pipes = server.settings.handler.pipeline.keys
            pipes.should contain :custom
          end

          it "have added pipes in the pipeline" do
            plugs = server.settings.handler.pipeline[:custom]
            plugs.first.should be_a Pipe::Logger
            plugs[1].should be_a Pipe::Error
          end

        end

        context "generating a multiple pipelines" do
          Amber::Server.configure do |app|
            pipeline :custom, :banzai do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end
          end

          it "should add all pipelines to the server's pipeline" do
            pipes = server.settings.handler.pipeline.keys
            pipes.should contain :custom
            pipes.should contain :banzai
          end

          it "have added pipes in the pipeline" do
            [:custom, :banzai].each do |name|
              plugs = server.settings.handler.pipeline[name]
              plugs.first.should be_a Pipe::Logger
              plugs[1].should be_a Pipe::Error
            end
          end
        end

      end
    end

  end
end
