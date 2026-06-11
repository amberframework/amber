# NOTE: Constants should be set before require begins.

ENV["AMBER_ENV"] = "test"
ENV[Amber::Support::ENCRYPT_ENV] = "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw"
TEST_PATH   = "spec/support/sample"
PUBLIC_PATH = TEST_PATH + "/public"
VIEWS_PATH  = TEST_PATH + "/views"
CURRENT_DIR = Dir.current

Amber.path = "./spec/support/config"
Amber.env=(ENV["AMBER_ENV"])

require "http"
require "spec"
require "../src/amber"
require "./support/fixtures"
require "./support/helpers"

include Helpers
