require "amber"
require "../config/*"
require "./models/**"
require "./mailers/**"
require "./handlers/**"

# load the application_controller before controllers which depend on it
require "./controllers/application_controller"
require "./controllers/**"

Amber::Server.start
