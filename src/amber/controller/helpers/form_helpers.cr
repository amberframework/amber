require "html"

module Amber::Controller::Helpers
  module FormHelpers
    # Generates an HTML form tag with automatic CSRF token inclusion.
    # For non-GET/POST methods, a hidden `_method` field is emitted.
    #
    # ```
    # form_for("/users", method: "POST") { "<input />" }
    # ```
    def form_for(action : String, method : String = "POST", **attrs, &block : -> String) : String
      actual_method = method.upcase
      form_method = (actual_method == "GET") ? "GET" : "POST"

      result = String::Builder.new
      result << "<form action=\"#{HTML.escape(action)}\" method=\"#{form_method}\""
      attrs.each do |key, value|
        case value
        when Bool
          result << " #{key}" if value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(value.to_s)}\""
        end
      end
      result << ">"

      # Include method override for non-GET/POST methods
      if actual_method != "GET" && actual_method != "POST"
        result << hidden_field("_method", actual_method)
      end

      # Include CSRF token for non-GET forms
      if actual_method != "GET"
        result << csrf_tag
      end

      result << block.call
      result << "</form>"
      result.to_s
    end

    # Generates a text input field.
    #
    # ```
    # text_field("name")                        # => "<input type=\"text\" name=\"name\" id=\"name\" />"
    # text_field("name", value: "John")         # => "<input type=\"text\" name=\"name\" id=\"name\" value=\"John\" />"
    # text_field("name", class: "form-control") # => "<input type=\"text\" name=\"name\" id=\"name\" class=\"form-control\" />"
    # ```
    def text_field(name : String, value : String? = nil, **attrs) : String
      input_field("text", name, value, **attrs)
    end

    # Generates an email input field.
    def email_field(name : String, value : String? = nil, **attrs) : String
      input_field("email", name, value, **attrs)
    end

    # Generates a password input field. Never includes a value attribute.
    def password_field(name : String, **attrs) : String
      input_field("password", name, nil, **attrs)
    end

    # Generates a number input field.
    def number_field(name : String, value : Number? = nil, **attrs) : String
      input_field("number", name, value.try(&.to_s), **attrs)
    end

    # Generates a hidden input field.
    def hidden_field(name : String, value : String) : String
      input_field("hidden", name, value)
    end

    # Generates a textarea element.
    #
    # ```
    # text_area("bio")                 # => "<textarea name=\"bio\" id=\"bio\"></textarea>"
    # text_area("bio", value: "Hello") # => "<textarea name=\"bio\" id=\"bio\">Hello</textarea>"
    # ```
    def text_area(name : String, value : String? = nil, **attrs) : String
      result = String::Builder.new
      result << "<textarea name=\"#{HTML.escape(name)}\" id=\"#{HTML.escape(name)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << ">"
      result << HTML.escape(value) if value
      result << "</textarea>"
      result.to_s
    end

    # Generates a select dropdown field.
    #
    # ```
    # select_field("color", [{"Red", "red"}, {"Blue", "blue"}], selected: "blue")
    # select_field("size", ["Small", "Medium", "Large"])
    # ```
    def select_field(name : String, options : Array, selected : String? = nil, **attrs) : String
      result = String::Builder.new
      result << "<select name=\"#{HTML.escape(name)}\" id=\"#{HTML.escape(name)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << ">"

      options.each do |option|
        case option
        when Tuple(String, String)
          label, val = option
          selected_attr = (selected && val == selected) ? " selected" : ""
          result << "<option value=\"#{HTML.escape(val)}\"#{selected_attr}>#{HTML.escape(label)}</option>"
        when String
          selected_attr = (selected && option == selected) ? " selected" : ""
          result << "<option value=\"#{HTML.escape(option)}\"#{selected_attr}>#{HTML.escape(option)}</option>"
        end
      end

      result << "</select>"
      result.to_s
    end

    # Generates a checkbox input field.
    #
    # ```
    # checkbox("remember_me")          # => "<input type=\"checkbox\" name=\"remember_me\" id=\"remember_me\" />"
    # checkbox("terms", checked: true) # => "<input type=\"checkbox\" name=\"terms\" id=\"terms\" checked />"
    # ```
    def checkbox(name : String, checked : Bool = false, **attrs) : String
      result = String::Builder.new
      result << "<input type=\"checkbox\" name=\"#{HTML.escape(name)}\" id=\"#{HTML.escape(name)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << " checked" if checked
      result << " />"
      result.to_s
    end

    # Generates a radio button input field.
    #
    # ```
    # radio_button("color", "red")                 # => "<input type=\"radio\" name=\"color\" id=\"color_red\" value=\"red\" />"
    # radio_button("color", "blue", checked: true) # => "<input type=\"radio\" name=\"color\" id=\"color_blue\" value=\"blue\" checked />"
    # ```
    def radio_button(name : String, value : String, checked : Bool = false, **attrs) : String
      result = String::Builder.new
      result << "<input type=\"radio\" name=\"#{HTML.escape(name)}\" id=\"#{HTML.escape(name)}_#{HTML.escape(value)}\" value=\"#{HTML.escape(value)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << " checked" if checked
      result << " />"
      result.to_s
    end

    # Generates a label element.
    #
    # ```
    # label("email")                     # => "<label for=\"email\">Email</label>"
    # label("email", text: "Your Email") # => "<label for=\"email\">Your Email</label>"
    # ```
    def label(for_field : String, text : String? = nil, **attrs) : String
      display_text = text || for_field.capitalize
      result = String::Builder.new
      result << "<label for=\"#{HTML.escape(for_field)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << ">#{HTML.escape(display_text)}</label>"
      result.to_s
    end

    # Generates a submit button.
    #
    # ```
    # submit_button                     # => "<input type=\"submit\" value=\"Submit\" />"
    # submit_button("Save")             # => "<input type=\"submit\" value=\"Save\" />"
    # submit_button("Go", class: "btn") # => "<input type=\"submit\" value=\"Go\" class=\"btn\" />"
    # ```
    def submit_button(text : String = "Submit", **attrs) : String
      result = String::Builder.new
      result << "<input type=\"submit\" value=\"#{HTML.escape(text)}\""
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << " />"
      result.to_s
    end

    # Builds a standard input field. Used internally by the typed field helpers.
    private def input_field(type : String, name : String, value : String? = nil, **attrs) : String
      result = String::Builder.new
      result << "<input type=\"#{type}\" name=\"#{HTML.escape(name)}\" id=\"#{HTML.escape(name)}\""
      result << " value=\"#{HTML.escape(value)}\"" if value
      attrs.each do |key, attr_value|
        case attr_value
        when Bool
          result << " #{key}" if attr_value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(attr_value.to_s)}\""
        end
      end
      result << " />"
      result.to_s
    end
  end
end
