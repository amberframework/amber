require "http"
require "spec"
require "../src/amber"
require "../src/amber/cli/commands"
require "./amber/controller/*"
require "./support/**"

TEST_PATH    = "spec/support/sample"
PUBLIC_PATH  = TEST_PATH + "/public"
VIEWS_PATH   = TEST_PATH + "/views"
TESTING_APP  = "./test_app"
APP_TPL_PATH = "./src/amber/cli/templates/app"
CURRENT_DIR  = Dir.current

module Amber::CLI::Spec
  def self.cleanup
    puts "cleaning up..."
    Dir.cd CURRENT_DIR
    `rm -rf #{TESTING_APP}`
  end
end
