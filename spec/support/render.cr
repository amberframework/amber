require "../spec_helper"

class TestController < Amber::Controller::Base
  def render_template_page
    render_template("spec/sample/views/test.slang")
  end

  def render_layout_too
    render_both("spec/sample/views/test.slang", "spec/sample/views/layout.slang")
  end

  def render_both_inferred
    render("test.slang", "layout.slang", "spec/sample/views", "./")
  end
end

module Amber::Controller
  describe Amber::DSL::ControllerActions do 
    it "renders html from slang template" do
      TestController.new.render_template_page.should eq "<h1>Hello World</h1>\n<p>I am glad you came</p>"
    end

    it "renders html and layout from slang template" do
      TestController.new.render_layout_too.should eq "<html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>" 
    end

    it "renders html and layout from slang template" do
      TestController.new.render_both_inferred.should eq "<html>\n  <body>\n    <h1>Hello World</h1>\n<p>I am glad you came</p>\n  </body>\n</html>" 
    end
  end
end
