require "../../../spec_helper"

module Amber::Controller::Helpers
  describe TagHelpers do
    controller = build_controller

    describe "#tag" do
      it "generates a self-closing tag" do
        controller.tag("br").should eq "<br />"
      end

      it "generates a self-closing tag with attributes" do
        result = controller.tag("img", src: "/logo.png", alt: "Logo")
        result.should contain "<img"
        result.should contain "src=\"/logo.png\""
        result.should contain "alt=\"Logo\""
        result.should contain "/>"
      end

      it "generates an input tag with multiple attributes" do
        result = controller.tag("input", type: "text", name: "email", placeholder: "Enter email")
        result.should contain "type=\"text\""
        result.should contain "name=\"email\""
        result.should contain "placeholder=\"Enter email\""
      end

      it "escapes attribute values" do
        result = controller.tag("input", value: "<script>alert('xss')</script>")
        result.should contain "value=\"&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;\""
        result.should_not contain "<script>"
      end

      it "handles boolean true attributes" do
        result = controller.tag("input", type: "text", disabled: true)
        result.should contain "disabled"
        result.should contain "type=\"text\""
      end

      it "omits boolean false attributes" do
        result = controller.tag("input", type: "text", disabled: false)
        result.should_not contain "disabled"
        result.should contain "type=\"text\""
      end

      it "omits nil attributes" do
        result = controller.tag("input", type: "text", value: nil)
        result.should_not contain "value"
        result.should contain "type=\"text\""
      end
    end

    describe "#content_tag" do
      it "generates a tag with string content" do
        controller.content_tag("p", "Hello").should eq "<p>Hello</p>"
      end

      it "generates a tag with attributes and content" do
        result = controller.content_tag("div", "Content", class: "wrapper", id: "main")
        result.should contain "<div"
        result.should contain "class=\"wrapper\""
        result.should contain "id=\"main\""
        result.should contain ">Content</div>"
      end

      it "generates a tag with block content" do
        result = controller.content_tag("ul", class: "list") { "<li>Item</li>" }
        result.should contain "<ul"
        result.should contain "class=\"list\""
        result.should contain "><li>Item</li></ul>"
      end

      it "generates an empty tag when content is nil" do
        controller.content_tag("span").should eq "<span></span>"
      end

      it "handles attributes with no content" do
        result = controller.content_tag("div", class: "empty")
        result.should contain "<div"
        result.should contain "class=\"empty\""
        result.should contain "></div>"
      end
    end
  end
end
