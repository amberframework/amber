require "cli"
require "./cli/commands"
require "./version"
Amber::CLI::MainCommand.run ARGV
