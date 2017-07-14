require "amber"
require "../config/*"
require "./models/**"
require "./mailers/**"
require "./controllers/application_controller"
require "./controllers/**"

Amber::Server.instance.run
