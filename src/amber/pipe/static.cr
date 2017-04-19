module Amber
  module Pipe
    class Static < HTTP::StaticFileHandler
      property default_file, public_dir


      # class method to return a singleton instance of this Controller
      def self.instance
        @@instance ||= new
      end

      def initialize(public_dir : String, fallthrough = true)
        @public_dir = File.expand_path public_dir
        @fallthrough = !!fallthrough
        @default_file = nil
      end

      def initialize
        @public_dir = "./public"
        @default_file = "index.html"
        @fallthrough = true
      end

      private def mime_type(path)
        Support::MimeTypes.mime_type File.extname(path)
      end
    end
  end
end
