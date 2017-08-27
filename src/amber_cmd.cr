require "cli"
require "./amber/cmd/commands"

Amber::CMD::MainCommand.run ARGV
