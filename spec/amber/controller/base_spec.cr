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
      controller.responds_to?(:action_name).should eq true
      controller.responds_to?(:route_resource).should eq true
      controller.responds_to?(:route_scope).should eq true
      controller.responds_to?(:controller_name).should eq true
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

    describe "#respond_with" do
      request = HTTP::Request.new("GET", "")
      request.headers["Accept"] = ""
      context = create_context(request)

      it "respond_with html as default option" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "respond_with html" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.headers["Accept"] = "text/html"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "responds with json" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.headers["Accept"] = "application/json"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds with xml" do
        expected_result = "<xml><body><h1>Sort of xml</h1></body></xml>"
        context.request.headers["Accept"] = "application/xml"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/xml"
        context.response.status_code.should eq 200
      end

      it "responds with text" do
        expected_result = "Hello I'm text!"
        context.request.headers["Accept"] = "text/plain"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with json for path.json" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.path = "/response/1.json"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end

      it "responds with xml for path.xml" do
        expected_result = "<xml><body><h1>Sort of xml</h1></body></xml>"
        context.request.path = "/response/1.xml"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/xml"
        context.response.status_code.should eq 200
      end

      it "responds with text for path.txt" do
        expected_result = "Hello I'm text!"
        context.request.path = "/response/1.txt"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with text for path.text" do
        expected_result = "Hello I'm text!"
        context.request.path = "/response/1.text"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/plain"
        context.response.status_code.should eq 200
      end

      it "responds with 406 for path.text when text hasn't been defined" do
        expected_result = "Response Not Acceptable."
        context.request.path = "/response/1.text"
        ResponsesController.new(context).show.should eq expected_result
        context.response.status_code.should eq 406
      end

      it "respond with default if extension is invalid and accepts isn't defined" do
        expected_result = "<html><body><h1>Elorest <3 Amber</h1></body></html>"
        context.request.path = "/response/1.texas"
        context.request.headers["Accept"] = "text/html"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "text/html"
        context.response.status_code.should eq 200
      end

      it "responds with or accept header request if extension is invalid" do
        expected_result = %({"type":"json","name":"Amberator"})
        context.request.headers["Accept"] = "application/json"
        context.request.path = "/response/1.texas"
        ResponsesController.new(context).index.should eq expected_result
        context.response.headers["Content-Type"].should eq "application/json"
        context.response.status_code.should eq 200
      end
    end

    describe "#render" do
      request = HTTP::Request.new("GET", "")
      context = create_context(request)

      it "renders html from slang template" do
        RenderController.new(context).render_template_page.should eq page_template
      end

      it "renders partial without layout" do
        RenderController.new(context).render_partial.should eq partial_only
      end

      it "renders flash message" do
        RenderController.new(context).render_with_flash
      end

      it "renders html and layout from slang template" do
        RenderController.new(context).render_multiple_partials_in_layout.should eq layout_with_multiple_partials
      end

      it "renders html and layout from slang template" do
        RenderController.new(context).render_with_layout.should eq layout_with_template
      end

      it "renders a form with a csrf tag" do
        reuslt = RenderController.new(context).render_with_csrf
        reuslt.should contain "<form"
        reuslt.should contain "<input type=\"hidden\" name=\"_csrf\" value="
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
