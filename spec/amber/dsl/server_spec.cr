require "../../spec_helper"

module Amber
  class Server
    # Hello routes from pipeline_spec.cr aren't cleared with pipeline.clear,
    # which fails the spec 'should not have /hello route'.
    def self.reset_instance
      @@instance = nil
    end
  end

  module DSL
    def self.pipeline_custom
      server = Amber::Server.instance
      server.handler.pipeline.clear

      Amber::Server.configure do
        pipeline :custom do
          plug Pipe::Logger.new
          plug Pipe::Error.new
        end
      end

      server
    end

    def self.pipeline_custom_multi_and_single
      server = Amber::Server.instance
      server.handler.pipeline.clear

      Amber::Server.configure do
        pipeline :custom do
          plug Pipe::Logger.new
          plug Pipe::Error.new
        end

        pipeline :custom do
          plug Pipe::CSRF.new
        end
      end

      server
    end

    def self.all_pipelines
      server = Amber::Server.instance
      server.handler.pipeline.clear

      Amber::Server.configure do
        pipeline :api, :web do
          plug Pipe::Logger.new
          plug Pipe::Error.new
        end
      end

      server
    end

    def self.pipeline_multi_and_single
      server = Amber::Server.instance
      server.handler.pipeline.clear

      Amber::Server.configure do
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

      server
    end

    def self.pipeline_routes
      server = Amber::Server.instance
      server.handler.pipeline.clear

      Amber::Server.configure do
        pipeline :web do
        end

        pipeline :api do
        end

        routes :web do
          namespace "/test" do
            get "/hello", HelloController, :index

            namespace "/test2" do
              resources "/hello", HelloController, only: [:index, :create]
            end
          end
        end

        routes :api, "/api" do
          namespace "/test" do
            resources "/hello", HelloController, only: [:show, :update]
          end
        end
      end

      server
    end

    describe Server do
      describe "pipeline" do
        context "generating a single ':custom' pipeline" do
          it "should add ':custom' to the server's pipeline" do
            server = pipeline_custom

            valves = server.handler.pipeline.keys
            valves.should contain :custom
          end

          it "have added pipes in the pipeline" do
            server = pipeline_custom

            expected = [Pipe::Logger, Pipe::Error]
            plugs = server.handler.pipeline[:custom]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end
        end

        context "generating a single pipeline with multiple calls" do
          it "should have all pipes in pipeline" do
            server = pipeline_custom_multi_and_single

            expected = [Pipe::Logger, Pipe::Error, Pipe::CSRF]
            plugs = server.handler.pipeline[:custom]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end
        end

        context "generating multiple pipelines" do
          it "should add all pipelines to the server's pipeline" do
            server = all_pipelines

            valves = server.handler.pipeline.keys
            valves.should contain :api
            valves.should contain :web
          end

          it "have added shared pipes in all pipelines" do
            server = all_pipelines

            expected = [Pipe::Logger, Pipe::Error]
            [:api, :web].each do |name|
              plugs = server.handler.pipeline[name]?
              plugs.should_not be nil
              (plugs.map(&.class).should eq expected) if plugs
            end
          end
        end

        context "generating multiple pipelines and single pipelines" do
          it "existing pipes should be at the front of the pipeline" do
            server = pipeline_multi_and_single

            plugs = server.handler.pipeline[:api]?
            plugs.should_not be nil
            (plugs.first?.should be_a Pipe::CORS) if plugs
          end

          it "additional pipes should be at the end of the pipeline" do
            server = pipeline_multi_and_single

            plugs = server.handler.pipeline[:web]?
            plugs.should_not be nil
            (plugs.last?.should be_a Pipe::CSRF) if plugs
          end

          it "pipes should be in the same order when appending" do
            server = pipeline_multi_and_single

            expected = [Pipe::CORS, Pipe::Logger, Pipe::Error]
            plugs = server.handler.pipeline[:api]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end

          it "pipes should be in the same order when prepending" do
            server = pipeline_multi_and_single

            expected = [Pipe::Logger, Pipe::Error, Pipe::CSRF]
            plugs = server.handler.pipeline[:web]?
            plugs.should_not be nil
            (plugs.map(&.class).should eq expected) if plugs
          end
        end
      end

      describe "routes" do
        context "with a namespace" do
          it "should not have /hello route" do
            Amber::Server.reset_instance
            server = pipeline_routes

            request = HTTP::Request.new("GET", "/hello")
            server.router.route_defined?(request).should eq(false)
          end

          it "should have a /test/hello route" do
            server = pipeline_routes

            request = HTTP::Request.new("GET", "/test/hello")
            server.router.route_defined?(request).should eq(true)
          end

          it "should have a /test/test2/hello route" do
            server = pipeline_routes

            request_get = HTTP::Request.new("GET", "/test/test2/hello")
            request_post = HTTP::Request.new("POST", "/test/test2/hello")
            server.router.route_defined?(request_get).should eq(true)
            server.router.route_defined?(request_post).should eq(true)
          end

          it "should have a /api/test/hello route" do
            server = pipeline_routes

            request_get = HTTP::Request.new("GET", "/api/test/hello/:id")
            request_put = HTTP::Request.new("PUT", "/api/test/hello/:id")
            server.router.route_defined?(request_get).should eq(true)
            server.router.route_defined?(request_put).should eq(true)
          end
        end
      end
    end
  end
end
