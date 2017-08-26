require "http"
require "spec"
require "../src/amber"
require "./support/**"
require "./amber/controller/*"
require "../src/amber_cmd/**"

TESTING_APP  = "./testapp"
APP_TPL_PATH = "./src/templates/app"
CURRENT_DIR = Dir.current 
