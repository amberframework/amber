require "../../../spec_helper"

module Amber::Controller::Helpers
  describe FormHelpers do
    controller = build_controller

    describe "#form_for" do
      it "generates a form tag with default POST method" do
        result = controller.form_for("/users") { "" }
        result.should contain "<form"
        result.should contain "action=\"/users\""
        result.should contain "method=\"POST\""
        result.should contain "</form>"
      end

      it "includes CSRF tag in POST forms" do
        result = controller.form_for("/users") { "" }
        result.should contain "_csrf"
        result.should contain "type=\"hidden\""
      end

      it "does not include CSRF tag in GET forms" do
        result = controller.form_for("/search", method: "GET") { "" }
        result.should_not contain "_csrf"
      end

      it "uses POST method with _method override for PUT" do
        result = controller.form_for("/users/1", method: "PUT") { "" }
        result.should contain "method=\"POST\""
        result.should contain "name=\"_method\""
        result.should contain "value=\"PUT\""
      end

      it "uses POST method with _method override for DELETE" do
        result = controller.form_for("/users/1", method: "DELETE") { "" }
        result.should contain "method=\"POST\""
        result.should contain "name=\"_method\""
        result.should contain "value=\"DELETE\""
      end

      it "uses POST method with _method override for PATCH" do
        result = controller.form_for("/users/1", method: "PATCH") { "" }
        result.should contain "method=\"POST\""
        result.should contain "name=\"_method\""
        result.should contain "value=\"PATCH\""
      end

      it "includes block content" do
        result = controller.form_for("/users") { "<input type=\"text\" />" }
        result.should contain "<input type=\"text\" />"
      end

      it "includes additional attributes" do
        result = controller.form_for("/users", class: "form-inline", id: "user-form") { "" }
        result.should contain "class=\"form-inline\""
        result.should contain "id=\"user-form\""
      end

      it "escapes the action URL" do
        result = controller.form_for("/search?q=<script>") { "" }
        result.should contain "action=\"/search?q=&lt;script&gt;\""
      end
    end

    describe "#text_field" do
      it "generates a text input" do
        result = controller.text_field("name")
        result.should contain "type=\"text\""
        result.should contain "name=\"name\""
        result.should contain "id=\"name\""
      end

      it "includes a value when provided" do
        result = controller.text_field("name", value: "John")
        result.should contain "value=\"John\""
      end

      it "includes additional attributes" do
        result = controller.text_field("name", class: "form-control", placeholder: "Enter name")
        result.should contain "class=\"form-control\""
        result.should contain "placeholder=\"Enter name\""
      end

      it "escapes the value" do
        result = controller.text_field("name", value: "<script>")
        result.should contain "value=\"&lt;script&gt;\""
      end
    end

    describe "#email_field" do
      it "generates an email input" do
        result = controller.email_field("email")
        result.should contain "type=\"email\""
        result.should contain "name=\"email\""
      end

      it "includes a value when provided" do
        result = controller.email_field("email", value: "user@example.com")
        result.should contain "value=\"user@example.com\""
      end
    end

    describe "#password_field" do
      it "generates a password input without a value" do
        result = controller.password_field("password")
        result.should contain "type=\"password\""
        result.should contain "name=\"password\""
        result.should_not contain "value="
      end

      it "includes additional attributes" do
        result = controller.password_field("password", class: "secure")
        result.should contain "class=\"secure\""
      end
    end

    describe "#number_field" do
      it "generates a number input" do
        result = controller.number_field("quantity")
        result.should contain "type=\"number\""
        result.should contain "name=\"quantity\""
      end

      it "includes a numeric value" do
        result = controller.number_field("quantity", value: 5)
        result.should contain "value=\"5\""
      end

      it "handles nil value" do
        result = controller.number_field("quantity")
        result.should_not contain "value="
      end
    end

    describe "#hidden_field" do
      it "generates a hidden input with a value" do
        result = controller.hidden_field("token", "abc123")
        result.should contain "type=\"hidden\""
        result.should contain "name=\"token\""
        result.should contain "value=\"abc123\""
      end

      it "escapes the value" do
        result = controller.hidden_field("data", "<malicious>")
        result.should contain "value=\"&lt;malicious&gt;\""
      end
    end

    describe "#text_area" do
      it "generates a textarea element" do
        result = controller.text_area("bio")
        result.should eq "<textarea name=\"bio\" id=\"bio\"></textarea>"
      end

      it "includes content when value is provided" do
        result = controller.text_area("bio", value: "Hello there")
        result.should contain ">Hello there</textarea>"
      end

      it "escapes the value" do
        result = controller.text_area("bio", value: "<script>alert('xss')</script>")
        result.should contain "&lt;script&gt;"
        result.should_not contain "<script>"
      end

      it "includes additional attributes" do
        result = controller.text_area("bio", rows: "5", cols: "40")
        result.should contain "rows=\"5\""
        result.should contain "cols=\"40\""
      end
    end

    describe "#select_field" do
      it "generates a select element with string options" do
        result = controller.select_field("size", ["Small", "Medium", "Large"])
        result.should contain "<select name=\"size\" id=\"size\">"
        result.should contain "<option value=\"Small\">Small</option>"
        result.should contain "<option value=\"Medium\">Medium</option>"
        result.should contain "<option value=\"Large\">Large</option>"
        result.should contain "</select>"
      end

      it "generates a select element with tuple options" do
        result = controller.select_field("color", [{"Red", "red"}, {"Blue", "blue"}])
        result.should contain "<option value=\"red\">Red</option>"
        result.should contain "<option value=\"blue\">Blue</option>"
      end

      it "marks the selected option with string options" do
        result = controller.select_field("size", ["Small", "Medium", "Large"], selected: "Medium")
        result.should contain "<option value=\"Medium\" selected>Medium</option>"
        result.should_not contain "<option value=\"Small\" selected>"
      end

      it "marks the selected option with tuple options" do
        result = controller.select_field("color", [{"Red", "red"}, {"Blue", "blue"}], selected: "blue")
        result.should contain "<option value=\"blue\" selected>Blue</option>"
        result.should_not contain "<option value=\"red\" selected>"
      end

      it "includes additional attributes" do
        result = controller.select_field("size", ["Small"], class: "form-select")
        result.should contain "class=\"form-select\""
      end
    end

    describe "#checkbox" do
      it "generates an unchecked checkbox" do
        result = controller.checkbox("remember_me")
        result.should contain "type=\"checkbox\""
        result.should contain "name=\"remember_me\""
        result.should contain "id=\"remember_me\""
        result.should_not contain "checked"
      end

      it "generates a checked checkbox" do
        result = controller.checkbox("terms", checked: true)
        result.should contain "checked"
      end

      it "includes additional attributes" do
        result = controller.checkbox("terms", class: "form-check")
        result.should contain "class=\"form-check\""
      end
    end

    describe "#radio_button" do
      it "generates a radio button" do
        result = controller.radio_button("color", "red")
        result.should contain "type=\"radio\""
        result.should contain "name=\"color\""
        result.should contain "id=\"color_red\""
        result.should contain "value=\"red\""
        result.should_not contain "checked"
      end

      it "generates a checked radio button" do
        result = controller.radio_button("color", "blue", checked: true)
        result.should contain "checked"
      end

      it "includes additional attributes" do
        result = controller.radio_button("color", "red", class: "form-radio")
        result.should contain "class=\"form-radio\""
      end
    end

    describe "#label" do
      it "generates a label with auto-capitalized text" do
        result = controller.label("email")
        result.should eq "<label for=\"email\">Email</label>"
      end

      it "generates a label with custom text" do
        result = controller.label("email", text: "Your Email Address")
        result.should contain "for=\"email\""
        result.should contain ">Your Email Address</label>"
      end

      it "includes additional attributes" do
        result = controller.label("email", class: "form-label")
        result.should contain "class=\"form-label\""
      end

      it "escapes the text" do
        result = controller.label("field", text: "<b>Bold</b>")
        result.should contain "&lt;b&gt;Bold&lt;/b&gt;"
      end
    end

    describe "#submit_button" do
      it "generates a submit button with default text" do
        result = controller.submit_button
        result.should contain "type=\"submit\""
        result.should contain "value=\"Submit\""
      end

      it "generates a submit button with custom text" do
        result = controller.submit_button("Save")
        result.should contain "value=\"Save\""
      end

      it "includes additional attributes" do
        result = controller.submit_button("Go", class: "btn btn-primary")
        result.should contain "class=\"btn btn-primary\""
      end

      it "escapes the text" do
        result = controller.submit_button("<Click>")
        result.should contain "value=\"&lt;Click&gt;\""
      end
    end
  end
end
