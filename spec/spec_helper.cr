# NOTE: Constants should be set before require begins.

ENV["LAUNCH_ENV"] = "test"
ENV[Launch::Support::ENCRYPT_ENV] = "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw"
TEST_PATH         = "spec/support/sample"
PUBLIC_PATH       = TEST_PATH + "/public"
VIEWS_PATH        = TEST_PATH + "/views"
TEST_APP_NAME     = "test_app"
TESTING_APP       = "./tmp/#{TEST_APP_NAME}"
APP_TEMPLATE_PATH = "../../src/launch/cli/templates/app"
CURRENT_DIR       = Dir.current

Launch.path = "./spec/support/config"
Launch.env=(ENV["LAUNCH_ENV"])
Launch.settings.redis_url = ENV["REDIS_URL"] if ENV["REDIS_URL"]?

require "http"
require "spec"
require "../src/launch"
require "../src/launch/cli/commands"
require "./support/fixtures"
require "./support/helpers"

include Helpers
