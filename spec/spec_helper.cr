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
# The websocket helpers open clients with HTTP::WebSocket.new(String). Since
# agent-crystal 1.22.3-incremental-1 (crimson-knight/crystal#45) that constructor
# lives in http/web_socket/client, which require "http/web_socket" loads.
require "http/web_socket"
require "spec"
require "../src/amber"
require "./support/fixtures"
require "./support/helpers"
require "./support/fixture_compiler"

include Helpers
