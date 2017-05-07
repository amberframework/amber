require "../../../../spec_helper"

module Amber
  module Pipe
    describe Router do
      describe "http requests" do
        it "perform GET request" do
          request = HTTP::Request.new("GET", "/hello")
          router = Router.new
          router.draw :web { get "/hello", HelloController, :index}

          response = make_router_call(router, request)

          response.should eq "Index"
        end

        it "perform PUT request" do
          request = HTTP::Request.new("PUT", "/hello/1")
          router = Router.new
          router.draw :web { put "/hello/:id", HelloController, :update }

          response = make_router_call(router, request)

          response.should eq "Update"
        end

        it "perform PATCH request" do
          request = HTTP::Request.new("PATCH", "/hello/1")
          router = Router.new
          router.draw :web { patch "/hello/:id", HelloController, :update }

          response = make_router_call(router, request)

          response.should eq "Update"
        end

        it "perform POST request" do
          request = HTTP::Request.new("POST", "/hello")
          router = Router.new
          router.draw :web { post "/hello", HelloController, :create }

          response = make_router_call(router, request)

          response.should eq "Create"
        end

        it "perform DELETE request" do
          request = HTTP::Request.new("DELETE", "/hello/1")
          router = Router.new
          router.draw :web { delete "/hello/:id", HelloController, :destroy }

          response = make_router_call(router, request)

          response.should eq "Destroy"
        end
      end

      describe "#resources" do
        it "defines all resources" do
          router = Router.new

          router.draw :web do
            resources "/hello", HelloController
          end

          router.match("GET", "/hello").key.should eq "get/hello"
          router.match("GET", "/hello/2").key.should eq "get/hello/:id"
          router.match("GET", "/hello/2/new").key.should eq "get/hello/:id/new"
          router.match("GET", "/hello/2/edit").key.should eq "get/hello/:id/edit"
          router.match("PUT", "/hello/1").key.should eq "get/helloput/hello/:id"
          router.match("PATCH", "/hello/1").key.should eq "get/hellopatch/hello/:id"
          router.match("DELETE", "/hello/1").key.should eq "get/hellodelete/hello/:id"
          router.match("POST", "/hello").key.should eq "get/hellopost/hello"
        end

        context "when specifying actions" do
          it "defines only specified resources" do
            router = Router.new

            router.draw :web do
              resources "/hello", HelloController, only: [:index, :update]
            end

            router.match("GET", "/hello").key.should eq "get/hello"
            router.match("GET", "/hello/2").key.should eq ""
            router.match("GET", "/hello/2/new").key.should eq ""
            router.match("GET", "/hello/2/edit").key.should eq ""
            router.match("PUT", "/hello/1").key.should eq "get/helloput/hello/:id"
            router.match("PATCH", "/hello/1").key.should eq "get/hellopatch/hello/:id"
            router.match("DELETE", "/hello/1").key.should eq ""
          end

          it "defines resources excluding from list" do
            router = Router.new

            router.draw :web do
              resources "/hello", HelloController, except: [:index, :update]
            end

            router.match("GET", "/hello").key.should eq ""
            router.match("GET", "/hello/2").key.should eq "get/hello/:id"
            router.match("GET", "/hello/2/new").key.should eq "get/hello/:id/new"
            router.match("GET", "/hello/2/edit").key.should eq "get/hello/:id/edit"
            router.match("PUT", "/hello/1").key.should eq ""
            router.match("PATCH", "/hello/1").key.should eq ""
            router.match("DELETE", "/hello/1").key.should eq "get/hello/:iddelete/hello/:id"
          end
        end
      end

      describe "#call" do
        it "raises exception when route not found" do
          router = Router.new
          request = HTTP::Request.new("GET", "/bad/route")

          expect_raises Exceptions::RouteNotFound do
            create_request_and_return_io(router, request)
          end
        end

        it "routes" do
          router = Router.new
          request = HTTP::Request.new("GET", "/index/elias")

          router.draw :web do
            get "/index/:name", HelloController, :world
          end

          response = create_request_and_return_io(router, request)

          response.body.should eq "Hello World!"
        end
      end

      describe "#route_defined?" do
        it "returns false when route is not drawn" do
          router = Router.new
          request = HTTP::Request.new("GET", "/products/world")

          router.route_defined?(request).should eq false
        end

        it "returns true when route exists" do
          router = Router.new
          request = HTTP::Request.new("GET", "/hello/world")

          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }

          route = Route.new("GET", "/hello/world", handler)
          router.add(route)

          router.route_defined?(request).should eq true
        end
      end

      describe "#draw" do
        it "registers a route" do
          router = Router.new
          request = HTTP::Request.new("GET", "/checkout/elias")

          router.draw :web do
            get "/checkout/:name", HelloController, :world
          end

          route = router.match_by_request(request)
          route.found?.should eq true
          route.payload.verb.should eq "GET"
        end
      end

      describe "#add" do
        it "register a GET route" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }

          route = Route.new("GET", "/some/joe", handler)

          node = router.add(route)

          node.class.should eq Radix::Node(Amber::Route)
        end

        it "raises Amber::Exceptions::DuplicateRouteError on duplicate" do
          router = Router.new
          handler = ->(context : HTTP::Server::Context, action : Symbol){
            "hey world"
          }
          route = Route.new("GET", "/some/joe", handler)

          router.add(route)

          expect_raises Amber::Exceptions::DuplicateRouteError do
            router.add(route)
          end
        end
      end
    end
  end
end
