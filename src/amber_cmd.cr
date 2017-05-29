require "cli"
require "./amber_cmd/commands"

AMBER_YML    = ".amber.yml"
DATABASE_YML = "config/database.yml"

Amber::CMD::MainCommand.run ARGV
