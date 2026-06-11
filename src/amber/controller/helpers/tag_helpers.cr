require "html"

module Amber::Controller::Helpers
  module TagHelpers
    # Builds a self-closing HTML tag.
    #
    # ```
    # tag("br")                    # => "<br />"
    # tag("img", src: "/logo.png") # => "<img src=\"/logo.png\" />"
    # tag("input", type: "text", name: "email")
    # ```
    def tag(tag_name : String, **attrs) : String
      if attrs.empty?
        "<#{tag_name} />"
      else
        "<#{tag_name}#{tag_attributes(**attrs)} />"
      end
    end

    # Builds an HTML tag with content. Accepts either a content string or a block.
    #
    # ```
    # content_tag("p", "Hello")               # => "<p>Hello</p>"
    # content_tag("div", "Hi", class: "note") # => "<div class=\"note\">Hi</div>"
    # content_tag("ul") { "<li>Item</li>" }   # => "<ul><li>Item</li></ul>"
    # ```
    def content_tag(tag_name : String, content : String? = nil, **attrs, &block : -> String) : String
      inner = block.call
      if attrs.empty?
        "<#{tag_name}>#{inner}</#{tag_name}>"
      else
        "<#{tag_name}#{tag_attributes(**attrs)}>#{inner}</#{tag_name}>"
      end
    end

    def content_tag(tag_name : String, content : String? = nil, **attrs) : String
      inner = content || ""
      if attrs.empty?
        "<#{tag_name}>#{inner}</#{tag_name}>"
      else
        "<#{tag_name}#{tag_attributes(**attrs)}>#{inner}</#{tag_name}>"
      end
    end

    # Builds an HTML attributes string from keyword arguments.
    # Boolean `true` values produce valueless attributes (e.g. `disabled`).
    # `nil` and `false` values are omitted entirely.
    # All string values are HTML-escaped.
    private def tag_attributes(**attrs) : String
      result = String::Builder.new
      attrs.each do |key, value|
        case value
        when Bool
          result << " #{key}" if value
        when Nil
          # skip nil attributes
        else
          result << " #{key}=\"#{HTML.escape(value.to_s)}\""
        end
      end
      result.to_s
    end
  end
end
