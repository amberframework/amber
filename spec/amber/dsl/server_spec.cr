require "../../../spec_helper"

module Amber
  module DSL
    describe Server do

      describe "pipeline" do
        context "generating a single ':custom' pipeline" do
          server = Amber::Server.instance
          server.settings.handler.pipeline.clear
          Amber::Server.settings do |app|
            pipeline :custom do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end
          end

          it "should add ':custom' to the server's pipeline" do
            valves = server.settings.handler.pipeline.keys
            valves.should contain :custom
          end

          it "have added pipes in the pipeline" do
            expected = [Pipe::Logger, Pipe::Error]
            plugs = server.settings.handler.pipeline[:custom]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end

        end

        context "generating a single pipeline with multiple calls" do
          server = Amber::Server.instance
          server.settings.handler.pipeline.clear
          Amber::Server.settings do |app|
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
            plugs = server.settings.handler.pipeline[:custom]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end
        end

        context "generating multiple pipelines" do
          server = Amber::Server.instance
          server.settings.handler.pipeline.clear
          Amber::Server.settings do |app|
            pipeline :api, :web do
              plug Pipe::Logger.new
              plug Pipe::Error.new
            end
          end

          it "should add all pipelines to the server's pipeline" do
            valves = server.settings.handler.pipeline.keys
            valves.should contain :api
            valves.should contain :web
          end

          it "have added shared pipes in all pipelines" do
            expected = [Pipe::Logger, Pipe::Error]
            [:api, :web].each do |name|
              plugs = server.settings.handler.pipeline[name]?
              plugs.should_not be nil
              (plugs.map(&.class).should eq expected) if plugs
            end
          end
        end

        context "generating multiple pipelines and single pipelines" do
          server = Amber::Server.instance
          server.settings.handler.pipeline.clear
          Amber::Server.settings do |app|
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
            plugs = server.settings.handler.pipeline[:api]?
            plugs.should_not be nil
            (plugs.first?.should be_a Pipe::CORS) if plugs
          end

          it "additional pipes should be at the end of the pipeline" do
            plugs = server.settings.handler.pipeline[:web]?
            plugs.should_not be nil
            (plugs.last?.should be_a Pipe::CSRF) if plugs
          end

          it "pipes should be in the same order when appending" do
            expected = [Pipe::CORS, Pipe::Logger, Pipe::Error]
            plugs = server.settings.handler.pipeline[:api]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end

          it "pipes should be in the same order when prepending" do
            expected = [Pipe::Logger, Pipe::Error, Pipe::CSRF]
            plugs = server.settings.handler.pipeline[:web]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end
        end

      end
    end

  end
end
