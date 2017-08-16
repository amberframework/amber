require "../../../spec_helper"

module Amber::Controller
  describe Base do
    describe "#cookies" do
      it "responds to cookies" do
        controller = build_controller

        controller.responds_to?(:cookies).should eq true
      end
    end

    describe "#redirect_to" do
      it "responds to redirect_to" do
        controller = build_controller
        controller.responds_to?(:redirect_to).should eq true
      end
    end

    describe "#redirect_back" do
      it "responds to redirect_back" do
        controller = build_controller
        controller.responds_to?(:redirect_back).should eq true
      end
    end

    describe "#session" do
      it "responds to cookies" do
        controller = build_controller

        controller.responds_to?(:session).should eq true
      end

      it "sets a session value" do
        controller = build_controller

        controller.session["name"] = "David"

        controller.session["name"].should eq "David"
      end

      it "has a session id" do
        controller = build_controller

        controller.session.id.not_nil!.size.should eq 36
      end
    end

    describe "#render" do
      it "renders html from slang template" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <h1>Hello World</h1>\n<p>I am glad you came</p>
        HTML

        TestController.new(context).render_template_page.should eq html_output
      end

      it "renders partial without layout" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <h1>Hello World</h1>
        <p>I am glad you came</p>
        HTML

        TestController.new(context).render_partial.should eq html_output
      end

      it "renders flash message" do
        request = HTTP::Request.new("GET", "/")
        context = create_context(request)

        controller = TestController.new(context)

        controller.render_with_flash
      end

      it "renders html and layout from slang template" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>
        HTML

        TestController.new(context).render_with_layout.should eq html_output
      end

      it "renders a form with a csrf tag" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        csrf_token = Amber::Pipe::CSRF.token(context)
        html_output = <<-HTML
        <form action="/posts" method="post">
          <input type="hidden" name="_csrf" value="#{csrf_token}" />
          <div class="form-group">
            <input class="form-control" type="text" name="title" placeholder="Title" value="hey you">
          </div>
          <div class="form-group">
            <textarea class="form-control" rows="10" name="content" placeholder="Content">out there in the cold</textarea>
          </div>
          <button class="btn btn-primary btn-xs" type="submit">Submit</button>
          <a class="btn btn-default btn-xs" href="/posts">back</a>
        </form>
        HTML

        TestController.new(context).render_with_csrf.should eq html_output
      end
    end

    describe "#before_action" do
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
        it "raisees an error" do
          hello_controller = build_controller

          expect_raises Exceptions::Controller::Redirect do
            hello_controller.redirect_back
          end
        end
      end
    end
  end
end
