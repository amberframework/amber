module Amber
  module Pipe
    # Serves static files from the given public directory.
    #
    # Amber keeps directory listings disabled, applies the configured static
    # response headers, and gives content-addressed files an immutable cache
    # policy. A content-addressed filename ends in a SHA-256 fragment, for
    # example `app-0123456789abcdef.css`.
    #
    # An application with its own cache policy, for example a fingerprint
    # scheme other than Amber's, overrides `#cache_control` in a subclass. The
    # hook runs only for a file this pipe serves. A `Cache-Control` that an
    # earlier handler already set on the response is kept as it is.
    #
    # ```
    # class AppStatic < Amber::Pipe::Static
    #   SHORT_FINGERPRINT = /-[0-9a-f]{8}\.[^\/]+$/i
    #
    #   protected def cache_control(request_path : String) : String
    #     return IMMUTABLE_CACHE_CONTROL if request_path.matches?(SHORT_FINGERPRINT)
    #     super
    #   end
    # end
    # ```
    class Static < HTTP::StaticFileHandler
      FINGERPRINT_PATTERN = /-[0-9a-f]{16,64}\.[^\/]+$/i

      IMMUTABLE_CACHE_CONTROL  = "public, max-age=31536000, immutable"
      REVALIDATE_CACHE_CONTROL = "no-cache"

      # MIME registrations Crystal cannot consistently discover from the host
      # operating system. Keeping them here makes static responses portable
      # across macOS, Linux, and Windows.
      MIME_TYPES = {
        ".avif"        => "image/avif",
        ".cjs"         => "text/javascript; charset=utf-8",
        ".csv"         => "text/csv; charset=utf-8",
        ".css"         => "text/css; charset=utf-8",
        ".eot"         => "application/vnd.ms-fontobject",
        ".gif"         => "image/gif",
        ".htm"         => "text/html; charset=utf-8",
        ".html"        => "text/html; charset=utf-8",
        ".ico"         => "image/x-icon",
        ".jpeg"        => "image/jpeg",
        ".jpg"         => "image/jpeg",
        ".js"          => "text/javascript; charset=utf-8",
        ".json"        => "application/json; charset=utf-8",
        ".map"         => "application/json; charset=utf-8",
        ".mjs"         => "text/javascript; charset=utf-8",
        ".mp3"         => "audio/mpeg",
        ".mp4"         => "video/mp4",
        ".ogg"         => "audio/ogg",
        ".otf"         => "font/otf",
        ".pdf"         => "application/pdf",
        ".png"         => "image/png",
        ".svg"         => "image/svg+xml",
        ".ttf"         => "font/ttf",
        ".txt"         => "text/plain; charset=utf-8",
        ".wasm"        => "application/wasm",
        ".wav"         => "audio/wav",
        ".webm"        => "video/webm",
        ".webmanifest" => "application/manifest+json; charset=utf-8",
        ".webp"        => "image/webp",
        ".woff"        => "font/woff",
        ".woff2"       => "font/woff2",
        ".xml"         => "application/xml; charset=utf-8",
        ".zip"         => "application/zip",
      }

      @public_dir : Path
      @headers : HTTP::Headers
      @configured_cache_control : String?

      # Sets the default behavior for static file serving to _NOT_ list the
      # directory contents. Headers from `Amber.settings.static.headers` are
      # used unless an explicit hash is supplied.
      def initialize(
        public_dir : String,
        fallthrough = false,
        directory_listing = false,
        headers : Hash(String, String)? = nil,
      )
        @public_dir = Path.new(public_dir).expand
        @headers = HTTP::Headers.new
        (headers || Amber.settings.static.headers).each do |name, value|
          @headers[name] = value
        end
        # `#cache_control` applies the configured Cache-Control. HTTP::Headers
        # matches the name the way a response does (any case, `_` or `-`).
        @configured_cache_control = @headers["Cache-Control"]?
        @headers.delete("Cache-Control")

        register_portable_mime_types
        super(public_dir, fallthrough: !!fallthrough, directory_listing: !!directory_listing)
      end

      def call(context : HTTP::Server::Context) : Nil
        apply_asset_headers(context) if static_file?(context.request.path)
        super
      end

      private def apply_asset_headers(context : HTTP::Server::Context) : Nil
        policy_chosen_by_application = context.response.headers.has_key?("Cache-Control")
        @headers.each do |name, values|
          context.response.headers[name] = values
        end

        # A Cache-Control that an earlier handler set is the application's
        # decision and stays as it is.
        unless policy_chosen_by_application
          context.response.headers["Cache-Control"] = cache_control(context.request.path)
        end
        context.response.headers["X-Content-Type-Options"] ||= "nosniff"
        add_vary_accept_encoding(context.response.headers)
      end

      private def static_file?(request_path : String) : Bool
        return false if request_path.includes?('\0')

        decoded_path = URI.decode(request_path)
        path = Path.posix(decoded_path)
        expanded_path = path.expand("/")
        return false unless path == expanded_path

        File.file?(@public_dir.join(expanded_path.to_kind(Path::Kind.native)))
      rescue URI::Error
        false
      end

      # Returns the `Cache-Control` value for a static file at *request_path*.
      #
      # A content-addressed filename (see `FINGERPRINT_PATTERN`) is cached as
      # immutable; any other file gets the configured static `Cache-Control`,
      # or `no-cache`. Override it in a subclass to apply another policy.
      protected def cache_control(request_path : String) : String
        if fingerprinted?(request_path)
          IMMUTABLE_CACHE_CONTROL
        else
          @configured_cache_control || REVALIDATE_CACHE_CONTROL
        end
      end

      private def fingerprinted?(path : String) : Bool
        !!path.match(FINGERPRINT_PATTERN)
      end

      private def add_vary_accept_encoding(headers : HTTP::Headers) : Nil
        if current = headers["Vary"]?
          unless current.split(',').any? { |value| value.strip.downcase == "accept-encoding" }
            headers["Vary"] = "#{current}, Accept-Encoding"
          end
        else
          headers["Vary"] = "Accept-Encoding"
        end
      end

      private def register_portable_mime_types : Nil
        MIME_TYPES.each do |extension, content_type|
          MIME.register(extension, content_type)
        end
      end
    end
  end
end
