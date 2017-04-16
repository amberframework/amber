module Amber
  module Pipe
    class Static < Base
      property public_folder, default_file

      # class method to return a singleton instance of this Controller
      def self.instance
        @@instance ||= new
      end

      def initialize
        @public_folder = "./public"
        @default_file = "index.html"
      end

      def call(context)
        unless context.request.method == "GET" || context.request.method == "HEAD"
          call_next(context)
          return
        end

        public_dir = File.expand_path(@public_folder)
        request_path = URI.unescape(context.request.path.not_nil!)
        expanded_path = File.expand_path(request_path, "/")
        file_path = File.join(public_dir, expanded_path)
        file_path = File.join(public_dir, default_file) if file_path.ends_with? "/"

        if File.exists?(file_path)
          last_modified = File.stat(file_path).mtime.to_s("%a, %-d %h %C%y %T GMT")
          if modified_since = context.request.headers.fetch("If-Modified-Since", nil)
            if last_modified == modified_since
              context.response.status_code = 304
              return
            end
          end
          context.response.headers["Cache-Control"] = "public"
          context.response.headers["Last-Modified"] = last_modified
          context.response.content_type = mime_type(file_path)
          context.response.content_length = File.size(file_path)
          File.open(file_path) do |file|
            IO.copy(file, context.response)
          end
        else
          call_next(context)
        end
      end

      private def mime_type(path)
        case File.extname(path)
        when ".txt"          then "text/plain"
        when ".htm", ".html" then "text/html"
        when ".css"          then "text/css"
        when ".js"           then "application/javascript"
        when ".jpg"          then "image/jpeg"
        when ".png"          then "image/png"
        when ".svg"          then "image/svg+xml"
        else                      "application/octet-stream"
        end
      end
    end
  end
end
