require "../../../spec_helper"

module Amber
  module DSL
    describe Server do

      describe "pipeline" do
        context "generating a single ':custom' pipeline" do
          server = Amber::Server.new
          server.settings.handler.pipeline.clear
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
            plugs.first?.should be_a Pipe::Logger
            plugs[1]?.should be_a Pipe::Error
          end

        end

        context "generating a single pipeline with multiple calls" do
          server = Amber::Server.new
          server.settings.handler.pipeline.clear
          Amber::Server.configure do |app|
            pipeline :custom do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end

            pipeline :custom do
              plug Pipe::CSRF.new
            end
          end

          it "should have all pipes in pipeline" do
            expected = [Pipe::Logger, Pipe::Error, Pipe::CSRF]
            plugs = server.settings.handler.pipeline[:custom]
            plugs.map(&.class).should eq expected
          end
        end

        context "generating multiple pipelines" do
          server = Amber::Server.new
          server.settings.handler.pipeline.clear
          Amber::Server.configure do |app|
            pipeline :api, :web do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end
          end

          it "should add all pipelines to the server's pipeline" do
            pipes = server.settings.handler.pipeline.keys
            pipes.should contain :api
            pipes.should contain :web
          end

          it "have added shared pipes in all pipelines" do
            [:api, :web].each do |name|
              plugs = server.settings.handler.pipeline[name]
              plugs.first?.should be_a Pipe::Logger
              plugs[1]?.should be_a Pipe::Error
            end
          end
        end

        context "generating multiple pipelines and single pipelines" do
          server = Amber::Server.new
          server.settings.handler.pipeline.clear
          Amber::Server.configure do |app|
            pipeline :api do
              plug Pipe::CORS.new
            end

            pipeline :api, :web do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end

            pipeline :web do
              plug Pipe::CSRF.new
            end
          end

          it "existing pipes should be at the front of the pipeline" do
            plugs = server.settings.handler.pipeline[:api]
            plugs.first?.should be_a Pipe::CORS
          end

          it "additional pipes should be at the end of the pipeline" do
            plugs = server.settings.handler.pipeline[:web]
            plugs.last?.should be_a Pipe::CSRF
          end

          it "pipes should be in the same order when appending" do
            expected = [Pipe::CORS, Pipe::Logger, Pipe::Error]
            plugs = server.settings.handler.pipeline[:api]
            plugs.map(&.class).should eq expected
          end

          it "pipes should be in the same order when prepending" do
            expected = [Pipe::Logger, Pipe::Error, Pipe::CSRF]
            plugs = server.settings.handler.pipeline[:web]
            plugs.map(&.class).should eq expected
          end
        end

      end
    end

  end
end
