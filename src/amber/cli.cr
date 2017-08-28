require "cli"
require "./commands"
require "./version"
Amber::CLI::MainCommand.run ARGV
