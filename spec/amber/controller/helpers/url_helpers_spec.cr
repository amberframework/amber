require "../../../spec_helper"

module Amber::Controller::Helpers
  describe URLHelpers do
    describe "#link_to" do
      controller = build_controller

      it "generates an anchor tag" do
        result = controller.link_to("Home", "/")
        result.should eq "<a href=\"/\">Home</a>"
      end

      it "generates an anchor tag with attributes" do
        result = controller.link_to("Profile", "/users/1", class: "nav-link", id: "profile")
        result.should contain "<a href=\"/users/1\""
        result.should contain "class=\"nav-link\""
        result.should contain "id=\"profile\""
        result.should contain ">Profile</a>"
      end

      it "escapes the URL" do
        result = controller.link_to("Search", "/search?q=<script>")
        result.should contain "href=\"/search?q=&lt;script&gt;\""
      end

      it "escapes the text" do
        result = controller.link_to("<b>Bold</b>", "/")
        result.should contain "&lt;b&gt;Bold&lt;/b&gt;"
        result.should_not contain "<b>Bold</b>"
      end
    end

    describe "#button_to" do
      controller = build_controller

      it "generates a form with a submit button" do
        result = controller.button_to("Delete", "/users/1", method: "DELETE")
        result.should contain "<form"
        result.should contain "action=\"/users/1\""
        result.should contain "method=\"POST\""
        result.should contain "class=\"button_to\""
        result.should contain "name=\"_method\""
        result.should contain "value=\"DELETE\""
        result.should contain "type=\"submit\""
        result.should contain "value=\"Delete\""
        result.should contain "</form>"
      end

      it "includes CSRF tag for POST forms" do
        result = controller.button_to("Submit", "/action")
        result.should contain "_csrf"
      end

      it "does not include CSRF tag for GET forms" do
        result = controller.button_to("Search", "/search", method: "GET")
        result.should_not contain "_csrf"
        result.should contain "method=\"GET\""
      end

      it "includes additional attributes on the submit button" do
        result = controller.button_to("Delete", "/users/1", method: "DELETE", class: "btn-danger")
        result.should contain "class=\"btn-danger\""
      end
    end

    describe "#mail_to" do
      controller = build_controller

      it "generates a mailto link with email as text" do
        result = controller.mail_to("user@example.com")
        result.should eq "<a href=\"mailto:user@example.com\">user@example.com</a>"
      end

      it "generates a mailto link with custom text" do
        result = controller.mail_to("user@example.com", text: "Email us")
        result.should contain "href=\"mailto:user@example.com\""
        result.should contain ">Email us</a>"
      end

      it "includes additional attributes" do
        result = controller.mail_to("user@example.com", class: "email-link")
        result.should contain "class=\"email-link\""
      end

      it "escapes the email address" do
        result = controller.mail_to("user@example.com&more")
        result.should contain "mailto:user@example.com&amp;more"
      end
    end

    describe "#link_back" do
      it "generates a back link from referer header" do
        controller = build_controller(referer: "http://example.com/previous")
        result = controller.link_back
        result.should contain "href=\"http://example.com/previous\""
        result.should contain ">Back</a>"
      end

      it "uses custom text" do
        controller = build_controller(referer: "http://example.com/previous")
        result = controller.link_back(text: "Go Back")
        result.should contain ">Go Back</a>"
      end

      it "falls back to # when no referer" do
        controller = build_controller
        result = controller.link_back
        result.should contain "href=\"#\""
      end

      it "includes additional attributes" do
        controller = build_controller(referer: "http://example.com")
        result = controller.link_back(class: "back-btn")
        result.should contain "class=\"back-btn\""
      end
    end
  end
end
