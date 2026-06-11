require "../../../spec_helper"

module Amber::Controller::Helpers
  describe AssetHelpers do
    controller = build_controller

    describe "#image_tag" do
      it "generates an image tag" do
        result = controller.image_tag("/images/logo.png")
        result.should eq "<img src=\"/images/logo.png\" />"
      end

      it "includes alt text" do
        result = controller.image_tag("/images/logo.png", alt: "Company Logo")
        result.should contain "src=\"/images/logo.png\""
        result.should contain "alt=\"Company Logo\""
      end

      it "includes size attributes" do
        result = controller.image_tag("/photo.jpg", width: "200", height: "100")
        result.should contain "width=\"200\""
        result.should contain "height=\"100\""
      end

      it "escapes the src URL" do
        result = controller.image_tag("/images/<script>.png")
        result.should contain "src=\"/images/&lt;script&gt;.png\""
      end

      it "includes additional attributes" do
        result = controller.image_tag("/logo.png", class: "img-responsive", id: "logo")
        result.should contain "class=\"img-responsive\""
        result.should contain "id=\"logo\""
      end
    end

    describe "#stylesheet_link_tag" do
      it "generates a stylesheet link tag with default media" do
        result = controller.stylesheet_link_tag("/css/app.css")
        result.should contain "rel=\"stylesheet\""
        result.should contain "href=\"/css/app.css\""
        result.should contain "media=\"screen\""
        result.should contain "/>"
      end

      it "uses a custom media type" do
        result = controller.stylesheet_link_tag("/css/print.css", media: "print")
        result.should contain "media=\"print\""
        # Should not also have the default media="screen"
        result.scan(/media=/).size.should eq 1
      end

      it "includes additional attributes" do
        result = controller.stylesheet_link_tag("/css/app.css", integrity: "sha256-abc")
        result.should contain "integrity=\"sha256-abc\""
      end

      it "escapes the path" do
        result = controller.stylesheet_link_tag("/css/<malicious>.css")
        result.should contain "href=\"/css/&lt;malicious&gt;.css\""
      end
    end

    describe "#javascript_include_tag" do
      it "generates a script tag" do
        result = controller.javascript_include_tag("/js/app.js")
        result.should eq "<script src=\"/js/app.js\"></script>"
      end

      it "includes additional attributes" do
        result = controller.javascript_include_tag("/js/app.js", async: true, defer: true)
        result.should contain "async"
        result.should contain "defer"
      end

      it "escapes the path" do
        result = controller.javascript_include_tag("/js/<malicious>.js")
        result.should contain "src=\"/js/&lt;malicious&gt;.js\""
      end
    end

    describe "#favicon_tag" do
      it "generates a default favicon tag" do
        result = controller.favicon_tag
        result.should eq "<link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\" />"
      end

      it "generates a favicon tag with custom path" do
        result = controller.favicon_tag("/images/icon.png")
        result.should contain "href=\"/images/icon.png\""
        result.should contain "rel=\"icon\""
        result.should contain "type=\"image/x-icon\""
      end

      it "escapes the path" do
        result = controller.favicon_tag("/icons/<bad>.ico")
        result.should contain "href=\"/icons/&lt;bad&gt;.ico\""
      end
    end
  end
end
