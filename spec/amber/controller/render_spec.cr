require "../../spec_helper"
require "../../support/fixtures/render_fixtures"

include RenderFixtures

module Amber::Controller
  describe Base do
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

      it "renders with layout equal to false" do
        RenderLayoutFalseController.new(context).render_with_layout.should eq partial_only
      end

      # it "renders a form with a csrf tag" do
      #   result = RenderController.new(context).render_with_csrf
      #   result.should contain "<form"
      #   result.should contain "<input type=\"hidden\" name=\"_csrf\" value="
      # end
    end
  end
end
