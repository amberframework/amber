require "html"

module Amber::Controller::Helpers
  module AssetHelpers
    # Generates an image tag.
    #
    # ```
    # image_tag("/images/logo.png")              # => "<img src=\"/images/logo.png\" />"
    # image_tag("/images/logo.png", alt: "Logo") # => "<img src=\"/images/logo.png\" alt=\"Logo\" />"
    # image_tag("/photo.jpg", width: "200", height: "100")
    # ```
    def image_tag(src : String, **attrs) : String
      result = String::Builder.new
      result << "<img src=\"#{HTML.escape(src)}\""
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
      result << " />"
      result.to_s
    end

    # Generates a stylesheet link tag.
    #
    # ```
    # stylesheet_link_tag("/css/app.css")
    # # => "<link rel=\"stylesheet\" href=\"/css/app.css\" media=\"screen\" />"
    # ```
    def stylesheet_link_tag(path : String, **attrs) : String
      result = String::Builder.new
      result << "<link rel=\"stylesheet\" href=\"#{HTML.escape(path)}\""

      has_media = false
      attrs.each do |key, value|
        has_media = true if key.to_s == "media"
        case value
        when Bool
          result << " #{key}" if value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(value.to_s)}\""
        end
      end

      result << " media=\"screen\"" unless has_media
      result << " />"
      result.to_s
    end

    # Generates a script tag for including JavaScript.
    #
    # ```
    # javascript_include_tag("/js/app.js")
    # # => "<script src=\"/js/app.js\"></script>"
    # ```
    def javascript_include_tag(path : String, **attrs) : String
      result = String::Builder.new
      result << "<script src=\"#{HTML.escape(path)}\""
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
      result << "></script>"
      result.to_s
    end

    # Generates a favicon link tag.
    #
    # ```
    # favicon_tag                     # => "<link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\" />"
    # favicon_tag("/images/icon.png") # => "<link rel=\"icon\" type=\"image/x-icon\" href=\"/images/icon.png\" />"
    # ```
    def favicon_tag(path : String = "/favicon.ico") : String
      "<link rel=\"icon\" type=\"image/x-icon\" href=\"#{HTML.escape(path)}\" />"
    end
  end
end
