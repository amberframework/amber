{% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
  require "compress/gzip"
  require "compress/deflate"
{% else %}
  require "zlib"
{% end %}

module Amber
  module Pipe
    class Static < HTTP::StaticFileHandler
      def initialize(public_dir : String, fallthrough = false, directory_listing = false)
        super
      end

      def call(context : HTTP::Server::Context)
        return allow_get_or_head(context) unless method_get_or_head?(context.request.method)

        original_path = context.request.path.not_nil!
        request_path = URI.decode(original_path)

        # File path cannot contains '\0' (NUL) because all filesystem I know
        # don't accept '\0' character as file name.
        if request_path.includes? '\0'
          context.response.status_code = 400
          return
        end

        is_dir_path = dir_path? original_path
        expanded_path = File.expand_path(request_path, "/")
        expanded_path += "/" if is_dir_path && !dir_path?(expanded_path)
        is_dir_path = dir_path? expanded_path
        file_path = File.join(@public_dir, expanded_path)
        root_file = File.join(@public_dir, expanded_path, "index.html")

        if is_dir_path && File.exists? root_file
          return if etag(context, root_file)
          return serve_file(context, root_file)
        end

        is_dir_path = Dir.exists?(file_path) && !is_dir_path
        if request_path != expanded_path || is_dir_path
          redirect_to context, file_redirect_path(expanded_path, is_dir_path)
        end

        call_next_with_file_path(context, request_path, file_path)
      end

      private def dir_path?(path)
        path.ends_with? "/"
      end

      private def method_get_or_head?(method)
        method == "GET" || method == "HEAD"
      end

      private def allow_get_or_head(context)
        if @fallthrough
          call_next(context)
        else
          context.response.status_code = 405
          context.response.headers.add("Allow", "GET, HEAD")
        end

        nil
      end

      private def file_redirect_path(path, is_dir_path)
        "#{path}/#{is_dir_path ? "" : "/"}"
      end

      private def call_next_with_file_path(context, request_path, file_path)
        config = static_config

        if Dir.exists?(file_path)
          if config.is_a?(Hash) && config["dir_listing"] == true
            context.response.content_type = "text/html"
            directory_listing(context.response, request_path, file_path)
          else
            call_next(context)
          end
        elsif File.exists?(file_path)
          return if etag(context, file_path)
          serve_file(context, file_path)
        else
          call_next(context)
        end
      end

      private def static_config
        {"dir_listing" => @directory_listing, "gzip" => true}
      end

      private def etag(context, file_path)
        etag = %{W/"#{File.info(file_path).modification_time.to_unix}"}
        context.response.headers["ETag"] = etag
        return false if !context.request.headers["If-None-Match"]? || context.request.headers["If-None-Match"] != etag
        context.response.headers.delete "Content-Type"
        context.response.content_length = 0
        context.response.status_code = 304 # not modified
        true
      end

      private def mime_type(path)
        Support::MimeTypes.mime_type File.extname(path)
      end

      private def serve_file(env, path : String, mime_type : String? = nil)
        config = static_config
        file_path = File.expand_path(path, Dir.current)
        mime_type ||= mime_type(file_path)
        env.response.content_type = mime_type

        add_response_headers(env)

        minsize = 860 # http://webmasters.stackexchange.com/questions/31750/what-is-recommended-minimum-object-size-for-gzip-performance-benefits ??
        request_headers = env.request.headers
        filesize = File.size(file_path)

        File.open(file_path) do |file|
          next multipart(file, env) if next_multipart?(env)

          if request_headers.includes_word?("Accept-Encoding", "gzip") && config_gzip?(config) && filesize > minsize && Support::MimeTypes.zip_types(file_path)
            gzip_encoding(env, file)
          elsif request_headers.includes_word?("Accept-Encoding", "deflate") && config_gzip?(config) && filesize > minsize && Support::MimeTypes.zip_types(file_path)
            deflate_endcoding(env, file)
          else
            env.response.content_length = filesize
            IO.copy(file, env.response)
          end
        end
        return
      end

      private def add_response_headers(env : HTTP::Server::Context)
        pipes = Amber.settings.pipes
        default_headers = {
          "Accept-Ranges"          => "bytes",
          "X-Content-Type-Options" => "nosniff",
          "Cache-Control"          => "private, max-age=3600",
        } of String => Amber::Settings::SettingValue

        headers = if pipes.has_key?("static") && pipes["static"].has_key?("headers")
                    default_headers.merge(pipes["static"]["headers"])
                  else
                    default_headers
                  end
        headers.each do |key, value|
          env.response.headers[key] = value.as(String)
        end
      end

      private def next_multipart?(env)
        env.request.method == "GET" && env.request.headers.has_key?("Range")
      end

      private def config_gzip?(config)
        config.is_a?(Hash) && config["gzip"] == true
      end

      private def gzip_encoding(env, file)
        env.response.headers["Content-Encoding"] = "gzip"
        {% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
          Compress::Gzip::Writer.open(env.response) do |deflate|
            IO.copy(file, deflate)
          end
        {% else %}
          Gzip::Writer.open(env.response) do |deflate|
            IO.copy(file, deflate)
          end
        {% end %}
      end

      private def deflate_endcoding(env, file)
        env.response.headers["Content-Encoding"] = "deflate"
        {% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
          Compress::Deflate::Writer.open(env.response) do |deflate|
            IO.copy(file, deflate)
          end
        {% else %}
          Flate::Writer.open(env.response) do |deflate|
            IO.copy(file, deflate)
          end
        {% end %}
      end

      private def multipart(file, env)
        # See http://httpwg.org/specs/rfc7233.html
        fileb = file.size

        range = env.request.headers["Range"]
        match = range.match(/bytes=(\d{1,})-(\d{0,})/)

        startb = 0
        endb = 0

        if match
          if match.size >= 2
            startb = match[1].to_i { 0 }
          end

          if match.size >= 3
            endb = match[2].to_i { 0 }
          end
        end

        if endb == 0
          endb = fileb - 1
        end

        if startb < endb && endb < fileb
          content_length = 1 + endb - startb
          env.response.status_code = 206
          env.response.content_length = content_length
          env.response.headers["Accept-Ranges"] = "bytes"
          env.response.headers["Content-Range"] = "bytes #{startb}-#{endb}/#{fileb}" # MUST

          if startb > 1024
            skipped = 0
            # file.skip only accepts values less or equal to 1024 (buffer size, undocumented)
            until skipped + 1024 > startb
              file.skip(1024)
              skipped += 1024
            end
            if skipped - startb > 0
              file.skip(skipped - startb)
            end
          else
            file.skip(startb)
          end

          IO.copy(file, env.response, content_length)
        else
          env.response.content_length = fileb
          env.response.status_code = 200 # Range not satisfiable, see 4.4 Note
          IO.copy(file, env.response)
        end
      end
    end
  end
end
