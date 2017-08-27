require "http"
require "spec"
require "../src/amber"
require "../src/amber/cmd/commands"
require "./amber/core/support/**"
require "./amber/core/controller/*"

TESTING_APP  = "./testapp"
APP_TPL_PATH = "./src/amber/cmd/templates/app"
CURRENT_DIR  = Dir.current

module Amber::CMD::Spec
  def self.cleanup
    puts "cleaning up..."
    Dir.cd(CURRENT_DIR)
    `rm -rf #{TESTING_APP}`
  end
end
