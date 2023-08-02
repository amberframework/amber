
module Amber
  module Pipe
    # Serves static files from the given public directory. By default, Amber turns off serving a directory listing page.
    class Static < HTTP::StaticFileHandler
      # Sets the default behavior for static file serving to _NOT_ list the directory contents.
      def initialize(public_dir : String, fallthrough = false, directory_listing = false)
        super
      end
    end
  end
end
