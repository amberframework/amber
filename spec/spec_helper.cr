# NOTE: Constants should be set before require begins.

ENV["AMBER_ENV"] = "test"
TEST_PATH         = "spec/support/sample"
PUBLIC_PATH       = TEST_PATH + "/public"
VIEWS_PATH        = TEST_PATH + "/views"
TEST_APP_NAME     = "test_app"
TESTING_APP       = "./tmp/#{TEST_APP_NAME}"
APP_TEMPLATE_PATH = "./src/amber/cli/templates/app"
CURRENT_DIR       = Dir.current

require "http"
require "spec"
require "../src/amber"
require "../src/amber/cli/commands"
require "./amber/controller/*"
require "./support/fixtures"
require "./support/helpers"

include Helpers
