require "cli"
require "./version"
require "./exceptions/*"
require "./environment"
require "./cli/commands"

Amber::CLI::MainCommand.run ARGV
