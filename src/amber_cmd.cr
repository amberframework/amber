require "cli"
require "./amber_cmd/commands"

Amber::CMD::MainCommand.run ARGV
