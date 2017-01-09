# This re-opens the Rendering Entry and checks for a + in the filename.
# If a + is found, then it will append to the existing file instead of
# overwrite it.
module Teeplate
  abstract class FileTree
    class Rendering
      class Entry
        def render
          if @local_path.includes? "+"
            @local_path = @local_path.gsub("+", "")
            puts " - appending #{@local_path}"
            File.open(out_path, "a") do |f|
              f.write slice
            end
          else
            if File.exists?(out_path) && !overwrites?
              puts " - skipping #{@local_path}. File exists."
            else
              puts " - creating #{@local_path}"
              File.open(out_path, "w") do |f|
                f.write slice
              end
            end
          end
        end
      end
    end
  end
end
