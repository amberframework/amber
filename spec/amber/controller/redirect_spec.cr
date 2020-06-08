require "../../spec_helper"

module Amber::Controller::Helpers
  describe Redirector do
    describe "#redirect" do
      it "redirects to location" do
        controller = build_controller
        redirector = Redirector.new("/some_path")
        redirector.redirect(controller)
        assert_expected_response?(controller, "/some_path", 302)
      end

      it "raises Exception::Controller::Redirect on invalid location" do
        controller = build_controller
        expect_raises Exceptions::Controller::Redirect do
          redirector = Redirector.new("", params: {"user_id" => "123"})
          redirector.redirect(controller)
        end
      end

      context "with params" do
        it "redirect to location and adds params to url" do
          controller = build_controller
          redirector = Redirector.new("/some_path", params: {"user_id" => "123"})
          redirector.redirect(controller)
          assert_expected_response?(controller, "/some_path?user_id=123", 302)
          controller.response.headers["location"] = ""
        end
      end

      context "with flash" do
        it "redirects to location and adds flash" do
          controller = build_controller
          redirector = Redirector.new("/some_path", flash: {"success" => "Record saved!"})
          redirector.redirect(controller)
          controller.flash["success"].should eq "Record saved!"
          assert_expected_response?(controller, "/some_path", 302)
        end
      end

      context "with a different status code" do
        it "redirects to location and sets a status code" do
          controller = build_controller
          redirector = Redirector.new("/some_path", status: 301)
          redirector.redirect(controller)
          assert_expected_response?(controller, "/some_path", 301)
        end
      end
    end

    describe ".from_controller_action" do
      Spec.before_suite do
        Amber::Server.router.draw :web do
          get "/redirect/:id", RedirectController, :show
          get "/redirect/:id/edit", RedirectController, :edit
          get "/redirect", RedirectController, :index
        end
      end

      it "raises an error for invalid controller/action" do
        expect_raises KeyError do
          Redirector.from_controller_action(:bad, :bad)
        end
      end

      it "redirects to full controller name as symbol" do
        # tmp fix for current travis crystal version.
        Amber::Server.router.draw :web do
          get "/redirect/:id", RedirectController, :show
          get "/redirect/:id/edit", RedirectController, :edit
          get "/redirect", RedirectController, :index
        end
        controller = build_controller
        redirector = Redirector.from_controller_action(:redirect, :show, params: {"id" => "5"})
        redirector.redirect(controller)
        assert_expected_response?(controller, "/redirect/5", 302)
      end

      it "redirects to full controller name as string" do
        controller = build_controller
        redirector = Redirector.from_controller_action("redirect", :show, params: {"id" => "5"})
        redirector.redirect(controller)
        assert_expected_response?(controller, "/redirect/5", 302)
      end

      it "redirects to full controller name as class" do
        controller = build_controller
        redirector = Redirector.from_controller_action(RedirectController, :show, params: {"id" => "5"})
        redirector.redirect(controller)
        assert_expected_response?(controller, "/redirect/5", 302)
      end

      it "redirects to :show" do
        controller = build_controller
        redirector = Redirector.from_controller_action(:redirect, :show, params: {"id" => "11"})
        redirector.redirect(controller)
        assert_expected_response?(controller, "/redirect/11", 302)
      end

      it "redirects to edit action" do
        controller = build_controller
        redirector = Redirector.from_controller_action(:redirect, :edit, params: {"id" => "123"})
        redirector.redirect(controller)
        assert_expected_response?(controller, "/redirect/123/edit", 302)
      end
    end

    describe "#redirect_back" do
      it "sets the correct response headers" do
        controller = build_controller("/redirect")
        controller.redirect_back
        controller.response.headers["Location"].should eq "/redirect"
      end

      it "raises an error" do
        controller = build_controller("")
        expect_raises Exceptions::Controller::Redirect do
          controller.redirect_back
        end
      end
    end
  end
end
