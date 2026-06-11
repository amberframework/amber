require "html"

module Amber::Controller::Helpers
  module URLHelpers
    # Generates an anchor tag.
    #
    # ```
    # link_to("Home", "/") # => "<a href=\"/\">Home</a>"
    # link_to("Profile", "/users/1", class: "nav-link")
    # ```
    def link_to(text : String, url : String, **attrs) : String
      result = String::Builder.new
      result << "<a href=\"#{HTML.escape(url)}\""
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
      result << ">#{HTML.escape(text)}</a>"
      result.to_s
    end

    # Generates a form containing a single submit button for non-GET actions.
    # Useful for delete links and other actions that should not be plain links.
    #
    # ```
    # button_to("Delete", "/users/1", method: "DELETE")
    # ```
    def button_to(text : String, url : String, method : String = "POST", **attrs) : String
      actual_method = method.upcase
      form_method = (actual_method == "GET") ? "GET" : "POST"

      result = String::Builder.new
      result << "<form action=\"#{HTML.escape(url)}\" method=\"#{form_method}\" class=\"button_to\">"

      if actual_method != "GET" && actual_method != "POST"
        result << hidden_field("_method", actual_method)
      end

      if actual_method != "GET"
        result << csrf_tag
      end

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
      result << "</form>"
      result.to_s
    end

    # Generates a mailto link.
    #
    # ```
    # mail_to("user@example.com")                   # => "<a href=\"mailto:user@example.com\">user@example.com</a>"
    # mail_to("user@example.com", text: "Email us") # => "<a href=\"mailto:user@example.com\">Email us</a>"
    # ```
    def mail_to(email : String, text : String? = nil, **attrs) : String
      display = text || email
      result = String::Builder.new
      result << "<a href=\"mailto:#{HTML.escape(email)}\""
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
      result << ">#{HTML.escape(display)}</a>"
      result.to_s
    end

    # Generates a link back to the previous page using the Referer header.
    # Falls back to "#" if no referer is present.
    #
    # ```
    # link_back                  # => "<a href=\"/previous\">Back</a>"
    # link_back(text: "Go Back") # => "<a href=\"/previous\">Go Back</a>"
    # ```
    def link_back(text : String = "Back", **attrs) : String
      referer = request.headers["Referer"]?
      url = (referer && !referer.empty?) ? referer : "#"
      link_to(text, url, **attrs)
    end
  end
end
