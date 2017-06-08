AMBER_ENV = ARGV[0]? || ENV["AMBER_ENV"]? || "development"

require "amber"
require "./**"
require "./*"
require "../config/*"

Amber::Server.instance.run
