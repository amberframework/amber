require "../../spec_helper"

module Amber
  module Router
    describe "Constraint DSL" do
      describe "route with as: parameter" do
        it "stores the name on the route" do
          router = Router.new
          router.draw :web do
            get "/users", HelloController, :index, route_name: :users
          end

          route = router.match_by_name(:users)
          route.should_not be_nil
          route.not_nil!.name.should eq :users
        end

        it "registers both the HTTP path and the name" do
          router = Router.new
          router.draw :web do
            get "/named_test", HelloController, :index, route_name: :named_test
          end

          # Path-based matching still works
          result = router.match("GET", "/named_test")
          result.found?.should be_true

          # Name-based lookup also works
          route = router.match_by_name(:named_test)
          route.should_not be_nil
        end
      end

      describe "constraint block" do
        it "attaches constraint to routes inside the block" do
          router = Router.new
          router.draw :web do
            constraint Amber::Router::Constraints::Header.new("X-Test", "yes") do
              get "/constrained", HelloController, :index
            end
          end

          result = router.match("GET", "/constrained")
          result.found?.should be_true

          route = result.payload.not_nil!
          route.request_constraint.should_not be_nil
        end

        it "does not attach constraint to routes outside the block" do
          router = Router.new
          router.draw :web do
            get "/unconstrained_before", HelloController, :index
            constraint Amber::Router::Constraints::Header.new("X-Test", "yes") do
              get "/constrained_inner", HelloController, :show
            end
            get "/unconstrained_after", HelloController, :new
          end

          unconstrained_before = router.match("GET", "/unconstrained_before")
          unconstrained_before.payload.not_nil!.request_constraint.should be_nil

          constrained = router.match("GET", "/constrained_inner")
          constrained.payload.not_nil!.request_constraint.should_not be_nil

          unconstrained_after = router.match("GET", "/unconstrained_after")
          unconstrained_after.payload.not_nil!.request_constraint.should be_nil
        end
      end

      describe "api_version macro with URL strategy" do
        it "creates versioned routes with namespace prefix" do
          router = Router.new
          router.draw :api do
            api_version "v1", prefix: "/api" do
              get "/users", HelloController, :index
            end

            api_version "v2", prefix: "/api" do
              get "/users", HelloController, :show
            end
          end

          v1 = router.match("GET", "/api/v1/users")
          v1.found?.should be_true
          v1.payload.not_nil!.action.should eq :index

          v2 = router.match("GET", "/api/v2/users")
          v2.found?.should be_true
          v2.payload.not_nil!.action.should eq :show
        end
      end

      describe "api_version macro with header strategy" do
        it "creates constrained routes for header-based versioning" do
          router = Router.new
          router.draw :api do
            api_version "v1", strategy: :header, header: "Api-Version" do
              get "/api/users", HelloController, :index
            end
          end

          result = router.match("GET", "/api/users")
          result.found?.should be_true

          route = result.payload.not_nil!
          route.request_constraint.should_not be_nil

          # Verify the constraint matches the expected header
          constraint = route.request_constraint.not_nil!
          matching_request = HTTP::Request.new("GET", "/api/users", HTTP::Headers{"Api-Version" => "v1"})
          constraint.matches?(matching_request).should be_true

          non_matching_request = HTTP::Request.new("GET", "/api/users", HTTP::Headers{"Api-Version" => "v2"})
          constraint.matches?(non_matching_request).should be_false
        end
      end

      describe "api_version macro with media_type strategy" do
        it "creates constrained routes for Accept header versioning" do
          router = Router.new
          router.draw :api do
            api_version "v1", strategy: :media_type, media_type: "application/vnd.myapp" do
              get "/api/data", HelloController, :index
            end
          end

          result = router.match("GET", "/api/data")
          result.found?.should be_true

          route = result.payload.not_nil!
          constraint = route.request_constraint.not_nil!

          matching = HTTP::Request.new("GET", "/api/data", HTTP::Headers{"Accept" => "application/vnd.myapp.v1+json"})
          constraint.matches?(matching).should be_true

          non_matching = HTTP::Request.new("GET", "/api/data", HTTP::Headers{"Accept" => "application/json"})
          constraint.matches?(non_matching).should be_false
        end
      end
      describe "nested constraint blocks" do
        it "requires a route inside both blocks to meet both" do
          router = Router.new
          router.draw :web do
            constraint Amber::Router::Constraints::Header.new("X-Outer", "yes") do
              constraint Amber::Router::Constraints::Header.new("X-Inner", "yes") do
                get "/nested-constrained", HelloController, :index
              end
            end
          end

          constraint = router.match("GET", "/nested-constrained").payload.not_nil!.request_constraint.not_nil!
          constraint.matches?(HTTP::Request.new("GET", "/nested-constrained", HTTP::Headers{"X-Inner" => "yes"})).should be_false
          constraint.matches?(HTTP::Request.new("GET", "/nested-constrained", HTTP::Headers{"X-Inner" => "yes", "X-Outer" => "yes"})).should be_true
        end
      end

      describe "websocket inside a constraint block" do
        it "picks the socket whose constraint the handshake meets when two share a path" do
          Amber::Server.router.draw :web do
            constraint Amber::Router::Constraints::Header.new("X-Socket-Tenant", "a") do
              websocket "/constrained-shared-socket", UserSocket
            end
            constraint Amber::Router::Constraints::Header.new("X-Socket-Tenant", "b") do
              websocket "/constrained-shared-socket", UserSocket
            end
          end
          list_of_handlers = Amber::Server.router.socket_routes
            .select { |socket_route| socket_route[:path] == "/constrained-shared-socket" }
            .map(&.[:handler])

          tenant_b = HTTP::Request.new("GET", "/constrained-shared-socket", HTTP::Headers{"X-Socket-Tenant" => "b"})
          Amber::Server.router.get_socket_handler(tenant_b).should be list_of_handlers.last

          tenant_c = HTTP::Request.new("GET", "/constrained-shared-socket", HTTP::Headers{"X-Socket-Tenant" => "c"})
          expect_raises(Amber::Exceptions::RouteNotFound) { Amber::Server.router.get_socket_handler(tenant_c) }
        end

        it "holds a socket to every enclosing block" do
          Amber::Server.router.draw :web do
            constraint Amber::Router::Constraints::Header.new("X-Outer", "yes") do
              constraint Amber::Router::Constraints::Header.new("X-Inner", "yes") do
                websocket "/nested-constrained-socket", UserSocket
              end
            end
          end

          inner_only = HTTP::Request.new("GET", "/nested-constrained-socket", HTTP::Headers{"X-Inner" => "yes"})
          expect_raises(Amber::Exceptions::RouteNotFound) { Amber::Server.router.get_socket_handler(inner_only) }

          both = HTTP::Request.new("GET", "/nested-constrained-socket", HTTP::Headers{"X-Inner" => "yes", "X-Outer" => "yes"})
          Amber::Server.router.get_socket_handler(both).should be_a(Amber::WebSockets::Server::Handler)
        end
      end
    end
  end
end
