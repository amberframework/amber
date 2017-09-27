require "../../../spec_helper"

module Amber::Controller
  describe Base do
    it "responds to context methods" do
      controller = build_controller
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
      it "responds to redirect_back" do
        controller = build_controller
        controller.responds_to?(:redirect_back).should eq true
      end
    end

    describe "#session" do
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
        <html>
          <body>
            <h1>
              <h1>Hello World</h1>
        <p>I am glad you came</p>
            </h1>
            <h2>
              <p>second partial</p>
            </h2>
            <h1>Hello World</h1>
        <p>I am glad you came</p>
          </body>
        </html>
        HTML

        TestController.new(context).render_multiple_partials_in_layout.should eq html_output
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
  end
end
