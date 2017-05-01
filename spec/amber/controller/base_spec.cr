require "../../../spec_helper"

module Amber::Controller
  describe Base do

    describe "#render" do
      it "renders html from slang template" do
        html_output = <<-HTML
        <h1>Hello World</h1>\n<p>I am glad you came</p>
        HTML

        TestController.new.render_template_page.should eq html_output
      end

      it "renders html and layout from slang template" do
        html_output = <<-HTML
        <html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>
        HTML

        TestController.new.render_layout_too.should eq html_output
      end

      it "renders html and layout from slang template" do
        html_output = <<-HTML
        <html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>
        HTML

        TestController.new.render_both_inferred.should eq html_output
      end
    end


    describe "#before_action" do

      it "registers a before action" do
        controller = build_controller("")
        # controller.run_actions(:show)

        # puts controller.filters
        controller.run_actions(:before, :index)
        # controller.run_actions(:world)
      end

      it "runs filters" do
        controller = build_controller("")
        # filters = controller.register_before_actions
        # controller.run_actions(:index)
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
