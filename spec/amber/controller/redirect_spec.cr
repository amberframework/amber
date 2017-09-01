require "../../../spec_helper"

module Amber::Controller
  describe Redirector do
    describe "#redirect" do
      it "redirects to location" do
        controller = build_controller
        redirector = Redirector.new("/some_path")

        redirector.redirect(controller)

        controller.response.headers["location"].should eq "/some_path"
        controller.response.status_code.should eq 302
        controller.context.content.nil?.should eq false
      end

      it "raises Exception::Controller::Redirect on invalid location" do
        controller = build_controller

        expect_raises Exceptions::Controller::Redirect do
          redirector = Redirector.new("", params: {"user_id" => "123"})
        end
      end

      context "with params" do
        it "redirect to location and adds params to url" do
          controller = build_controller
          redirector = Redirector.new("/some_path", params: {"user_id" => "123"})

          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/some_path?user_id=123"
          controller.response.status_code.should eq 302
          controller.context.content.nil?.should eq false
        end
      end

      context "with flash" do
        it "redirects to location and adds flash" do
          controller = build_controller
          redirector = Redirector.new("/some_path", flash: {"success" => "Record saved!"})

          flash = controller.flash
          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/some_path"
          flash["success"].should eq "Record saved!"
          controller.response.status_code.should eq 302
          controller.context.content.nil?.should eq false
        end
      end

      context "with a different status code" do
        it "redirects to location and sets a status code" do
          controller = build_controller
          redirector = Redirector.new("/some_path", status = 301)

          flash = controller.flash
          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/some_path"
          controller.response.status_code.should eq 301
          controller.context.content.nil?.should eq false
        end
      end
    end

    describe ".from_controller_action" do
      it "raises an error for invalid controller/action" do
        router = Amber::Server.router
        router.draw :web { put "/invalid/:id", HelloController, :edit }
        controller = build_controller

        expect_raises Exceptions::Controller::Redirect do
          redirector = Redirector.from_controller_action("bad", :bad)
        end
      end

      context "when scope is present" do
        it "redirects to the correct scoped location" do
          router = Amber::Server.router
          router.draw :web, "/scoped" { delete "/hello/:id", HelloController, :destroy }
          controller = build_controller
          redirector = Redirector.from_controller_action("hello", :destroy, params: {"id" => "5"})

          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/scoped/hello/5"
          controller.response.status_code.should eq 302
          controller.context.content.nil?.should eq false
        end
      end

      context "with params" do
        it "redirects to correct location for given controller action" do
          router = Amber::Server.router
          router.draw :web { get "/fake/:id", HelloController, :show }
          controller = build_controller
          redirector = Redirector.from_controller_action("hello", :show, params: {"id" => "11"})

          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/fake/11"
          controller.response.status_code.should eq 302
          controller.context.content.nil?.should eq false
        end
      end

      context "without params" do
        it "redirects to correct location for given controller action" do
          router = Amber::Server.router
          router.draw :web { get "/fake", HelloController, :index }
          controller = build_controller
          redirector = Redirector.from_controller_action("hello", :index)

          redirector.redirect(controller)

          controller.response.headers["location"].should eq "/fake"
          controller.response.status_code.should eq 302
          controller.context.content.nil?.should eq false
        end
      end
    end

    describe "#redirect_back" do
      context "and has a valid referrer" do
        it "sets the correct response headers" do
          hello_controller = build_controller("/world")

          hello_controller.redirect_back
          response = hello_controller.response

          response.headers["Location"].should eq "/world"
        end
      end

      context "and does not have a referrer" do
        it "raises an error" do
          hello_controller = build_controller

          expect_raises Exceptions::Controller::Redirect do
            hello_controller.redirect_back
          end
        end
      end
    end
  end
end
