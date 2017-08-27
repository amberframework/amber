require "http"
require "spec"
require "../src/amber"
require "../src/amber/cmd/commands"
require "./support/**"
require "./amber/controller/*"

TESTING_APP  = "./testapp"
APP_TPL_PATH = "./src/amber/cmd/templates/app"
CURRENT_DIR = Dir.current 
