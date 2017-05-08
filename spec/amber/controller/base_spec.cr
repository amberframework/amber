require "../../../spec_helper"

module Amber::Controller
  describe Base do
    describe "#render" do
      it "renders html from slang template" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <h1>Hello World</h1>\n<p>I am glad you came</p>
        HTML

        TestController.new(context).render_template_page.should eq html_output
      end

      it "renders html and layout from slang template" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>
        HTML

        TestController.new(context).render_layout_too.should eq html_output
      end

      it "renders html and layout from slang template" do
        request = HTTP::Request.new("GET", "/?test=test")
        context = create_context(request)
        html_output = <<-HTML
        <html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>
        HTML

        TestController.new(context).render_both_inferred.should eq html_output
      end
    end

    describe "#before_action" do
      context "registering action filters" do
        it "registers a before action" do
          controller = build_controller("")
          controller.before_filters

          before_filters = controller.filters[:before]

          before_filters.size.should eq 5
        end

        it "registers a after action" do
          controller = build_controller("")
          controller.after_filters

          after_filters = controller.filters[:after]

          after_filters.size.should eq 2
        end
      end

      context "running filters" do
        it "runs before filters" do
          controller = build_controller("")
          controller.run_before_filter(:index)

          controller.total.should eq 4
        end

        it "runs after filters" do
          controller = build_controller("")
          controller.run_after_filter(:index)

          controller.total.should eq 2
        end
      end
    end

    describe "#redirect_to" do
      context "when location is a string" do
        ["www.amberio.com", "/world"].each do |location|
          it "sets the correct response headers" do
            hello_controller = build_controller("")
            hello_controller.redirect_to location

            response = hello_controller.response

            response.headers["Location"].should eq location
          end
        end
      end

      context "when location is a Symbol" do
        context "when is :back" do
          context "and has a valid referer" do
            it "sets the correct response headers" do
              hello_controller = build_controller("/world")
              hello_controller.redirect_to :back

              response = hello_controller.response

              response.headers["Location"].should eq "/world"
            end
          end

          context "and does not have a referer" do
            it "raisees an error" do
              hello_controller = build_controller("")

              expect_raises Exceptions::Controller::Redirect do
                hello_controller.redirect_to :back
              end
            end
          end
        end

        context "when is an action" do
          hello_controller = build_controller("/world")
          hello_controller.redirect_to :world

          response = hello_controller.response

          response.headers["Location"].should eq "/world"
        end
      end
    end
  end
end
