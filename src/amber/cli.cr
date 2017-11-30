require "cli"
require "./cli/commands"
require "./version"
require "./exceptions/*"
Amber::CLI::MainCommand.run ARGV
