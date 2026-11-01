require "../config/*"
require "./controllers/**"
require "./models/**"
require "./schemas/**"
require "./jobs/**"
require "./mailers/**"
require "./channels/**"

Amber::Server.start
