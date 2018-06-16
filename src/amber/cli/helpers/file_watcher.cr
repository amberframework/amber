module Amber
    class FileWatcher
      @file_timestamps = {} of String => String
  
      private def get_timestamp(file : String)
        File.info(file).mtime.to_s("%Y%m%d%H%M%S")
      end
  
      def scan_files(files)
        Dir.glob(files) do |file|
          timestamp = get_timestamp(file)
          if @file_timestamps[file]? != timestamp
            @file_timestamps[file] = timestamp
            yield file
          end
        end
      end
    end
  end
  