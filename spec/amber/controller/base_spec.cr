require "../../../spec_helper"
require "../../../support/fixtures/render_fixtures"

include RenderFixtures

module Amber::Controller
  describe Base do
    controller = build_controller

    it "responds to context methods" do
      controller.responds_to?(:redirect_to).should eq true
      controller.responds_to?(:cookies).should eq true
      controller.responds_to?(:format).should eq true
      controller.responds_to?(:port).should eq true
      controller.responds_to?(:requested_url).should eq true
      controller.responds_to?(:session).should eq true
      controller.responds_to?(:valve).should eq true
      controller.responds_to?(:request_handler).should eq true
      controller.responds_to?(:route).should eq true
      controller.responds_to?(:websocket?).should eq true
      controller.responds_to?(:get?).should eq true
      controller.responds_to?(:post?).should eq true
      controller.responds_to?(:patch?).should eq true
      controller.responds_to?(:put?).should eq true
      controller.responds_to?(:delete?).should eq true
      controller.responds_to?(:head?).should eq true
      controller.responds_to?(:client_ip).should eq true
      controller.responds_to?(:request).should eq true
      controller.responds_to?(:response).should eq true
    end

    describe "#redirect_back" do
      controller = build_controller

      it "responds to redirect_back" do
        controller.responds_to?(:redirect_back).should eq true
      end
    end

    describe "#session" do
      controller = build_controller
      controller.session["name"] = "David"

      it "sets a session value" do
        controller.session["name"].should eq "David"
      end

      it "has a session id" do
        controller.session.id.not_nil!.size.should eq 36
      end
    end

    describe "#render" do
      request = HTTP::Request.new("GET", "")
      context = create_context(request)
      csrf_form = form_with_csrf(Amber::Pipe::CSRF.token(context))

      it "renders html from slang template" do
        TestController.new(context).render_template_page.should eq page_template
      end

      it "renders partial without layout" do
        TestController.new(context).render_partial.should eq partial_only
      end

      it "renders flash message" do
        TestController.new(context).render_with_flash
      end

      it "renders html and layout from slang template" do
        TestController.new(context).render_multiple_partials_in_layout.should eq layout_with_multiple_partials
      end

      it "renders html and layout from slang template" do
        TestController.new(context).render_with_layout.should eq layout_with_template
      end

      it "renders a form with a csrf tag" do
        TestController.new(context).render_with_csrf.should eq csrf_form
      end
    end

    describe "controller before and after filters" do
      context "registering action filters" do
        it "registers a before action" do
          controller = build_controller
          controller.before_filters

          before_filters = controller.filters[:before]
          before_filters.size.should eq 5
        end

        it "registers a after action" do
          controller = build_controller
          controller.after_filters

          after_filters = controller.filters[:after]
          after_filters.size.should eq 2
        end
      end

      context "running filters" do
        it "runs before filters" do
          controller = build_controller
          controller.run_before_filter(:index)
          controller.total.should eq 4
        end

        it "runs after filters" do
          controller = build_controller
          controller.run_after_filter(:index)
          controller.total.should eq 2
        end
      end
    end
  end
end
