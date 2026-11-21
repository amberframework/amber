require "html"

module Amber::Controller::Helpers
  module AssetHelpers
    # Generates an image tag.
    #
    # ```
    # image_tag("images/logo.png") # resolves through the asset manifest
    # image_tag("images/logo.png", alt: "Logo")
    # image_tag("images/photo.jpg", width: "200", height: "100")
    # ```
    def image_tag(src : String, **attrs) : String
      if attrs.empty? && !Amber::Assets.public_reference?(src)
        return Amber::Assets.manifest.rendered_tags.fetch(:image, src) { render_image_tag(src, **attrs) }
      end
      render_image_tag(src, **attrs)
    end

    private def render_image_tag(src : String, **attrs) : String
      src = asset_path(src)
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
    # stylesheet_link_tag("stylesheets/app.css")
    # # Resolves the fingerprinted URL and adds its integrity value.
    # ```
    def stylesheet_link_tag(path : String, **attrs) : String
      if attrs.empty? && !Amber::Assets.public_reference?(path)
        return Amber::Assets.manifest.rendered_tags.fetch(:stylesheet, path) { render_stylesheet_link_tag(path, **attrs) }
      end
      render_stylesheet_link_tag(path, **attrs)
    end

    private def render_stylesheet_link_tag(path : String, **attrs) : String
      logical_path = path
      path = asset_path(path)
      result = String::Builder.new
      result << "<link rel=\"stylesheet\" href=\"#{HTML.escape(path)}\""

      has_media = false
      has_integrity = false
      has_crossorigin = false
      attrs.each do |key, value|
        has_media = true if key.to_s == "media"
        has_integrity = true if key.to_s == "integrity"
        has_crossorigin = true if key.to_s == "crossorigin"
        case value
        when Bool
          result << " #{key}" if value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(value.to_s)}\""
        end
      end

      unless has_integrity || Amber::Assets.public_reference?(logical_path)
        result << " integrity=\"#{HTML.escape(asset_integrity(logical_path))}\""
        result << " crossorigin=\"anonymous\"" unless has_crossorigin
      end
      result << " media=\"screen\"" unless has_media
      result << " />"
      result.to_s
    end

    # Generates a script tag for including JavaScript.
    #
    # ```
    # javascript_include_tag("javascript/app.js")
    # # Resolves the fingerprinted URL and adds its integrity value.
    # ```
    def javascript_include_tag(path : String, **attrs) : String
      if attrs.empty? && !Amber::Assets.public_reference?(path)
        return Amber::Assets.manifest.rendered_tags.fetch(:javascript_include, path) { render_javascript_include_tag(path, **attrs) }
      end
      render_javascript_include_tag(path, **attrs)
    end

    private def render_javascript_include_tag(path : String, **attrs) : String
      logical_path = path
      path = asset_path(path)
      result = String::Builder.new
      result << "<script src=\"#{HTML.escape(path)}\""
      has_integrity = false
      has_crossorigin = false
      attrs.each do |key, value|
        has_integrity = true if key.to_s == "integrity"
        has_crossorigin = true if key.to_s == "crossorigin"
        case value
        when Bool
          result << " #{key}" if value
        when Nil
          # skip
        else
          result << " #{key}=\"#{HTML.escape(value.to_s)}\""
        end
      end
      unless has_integrity || Amber::Assets.public_reference?(logical_path)
        result << " integrity=\"#{HTML.escape(asset_integrity(logical_path))}\""
        result << " crossorigin=\"anonymous\"" unless has_crossorigin
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
      return render_favicon_tag(path) if Amber::Assets.public_reference?(path)
      Amber::Assets.manifest.rendered_tags.fetch(:favicon, path) { render_favicon_tag(path) }
    end

    private def render_favicon_tag(path : String) : String
      resolved_path = asset_path(path)
      type = Amber::Assets.public_reference?(path) ? "image/x-icon" : Amber::Assets.entry(path).content_type
      "<link rel=\"icon\" type=\"#{HTML.escape(type)}\" href=\"#{HTML.escape(resolved_path)}\" />"
    end

    # Resolves a logical, build-authored asset name through the persisted
    # manifest. Already-public URLs remain unchanged for backwards compatibility.
    def asset_path(path : String) : String
      Amber::Assets.resolve(path)
    end

    # Returns the Subresource Integrity value recorded for a logical asset.
    def asset_integrity(path : String) : String
      Amber::Assets.integrity(path)
    end

    # Generates a safe inline import map and optional local module preloads.
    # Local values are resolved through the same asset manifest as other tags.
    def javascript_importmap_tag(
      imports : Hash(String, String),
      preload : Array(String) = [] of String,
    ) : String
      # A map of public URLs only needs no manifest, so it is rendered as is.
      all_public = imports.each_value.all? { |path| Amber::Assets.public_reference?(path) } &&
                   preload.all? { |path| Amber::Assets.public_reference?(path) }
      return render_javascript_importmap_tag(imports, preload) if all_public

      Amber::Assets.manifest.rendered_tags.fetch_importmap(imports, preload) do
        render_javascript_importmap_tag(imports, preload)
      end
    end

    private def render_javascript_importmap_tag(imports : Hash(String, String), preload : Array(String)) : String
      resolved_imports = imports.transform_values { |path| asset_path(path) }
      json = {"imports" => resolved_imports}.to_json
        .gsub('<', "\\u003c")
        .gsub('>', "\\u003e")
        .gsub('&', "\\u0026")

      result = String::Builder.new
      preload.each do |logical_path|
        resolved_path = asset_path(logical_path)
        result << "<link rel=\"modulepreload\" href=\"#{HTML.escape(resolved_path)}\""
        unless Amber::Assets.public_reference?(logical_path)
          result << " integrity=\"#{HTML.escape(asset_integrity(logical_path))}\" crossorigin=\"anonymous\""
        end
        result << " />\n"
      end
      result << "<script type=\"importmap\">#{json}</script>"
      result.to_s
    end
  end
end
