require "./mime/types"

module Amber::Router
  module Mime
    DEFAULT_TYPE           = "application/octet-stream"
    ZIP_FILE_EXTENSIONS    = %w(.htm .html .txt .css .js .svg .json .xml .otf .ttf .woff .woff2)
    ACCEPT_SEPARATOR_REGEX = /,|,\s/
    FORMAT_HEADER          = "Accept"
    TYPE_EXT_REGEX         = /\.(#{TYPES.keys.join("|")})$/

    # Returns the Mime Type for a given format or file extname.
    #
    # ```
    # Amber::Router::Mime.type("json")                  # => "application/json"
    # Amber::Router::Mime.type(".jpg")                  # => "image/jpeg"
    # Amber::Router::Mime.type("unknown")               # => "application/octet-stream"
    # Amber::Router::Mime.type("unknown", "text/plain") # => "text/plain"
    # ```
    def self.type(format, fallback = DEFAULT_TYPE)
      format = format[1..-1] if format.starts_with?('.')
      TYPES.fetch(format, fallback)
    end

    def self.zip_types(path)
      ZIP_FILE_EXTENSIONS.includes? ::File.extname(path)
    end

    def self.format(accepts)
      TYPES.key_for? accepts
    end

    def self.default
      DEFAULT_TYPE
    end

    def self.get_request_format(request)
      path_ext = request.path.match(TYPE_EXT_REGEX).try(&.[1])
      return path_ext if path_ext

      accept = request.headers[FORMAT_HEADER]?
      if accept && !accept.empty?
        accept = accept.split(";").first?.try(&.split(ACCEPT_SEPARATOR_REGEX)).try &.first
        return format(accept) if accept
      end

      "html"
    end
  end
end
