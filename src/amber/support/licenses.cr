module Amber::Support
  module Licenses
    def self.display
      {{ run("../scripts/licenses.cr").stringify }}
    end
  end
end

# NOTE: if we need any other cli options we should move this to a cli folder/file.
# Until then it makes most sense to leave it here.

if ARGV[0]? && ARGV[0]? == "--license"
  puts Amber::Support::Licenses.display 
  exit 0 
end
