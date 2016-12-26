require "cli"
require "./kemalyst-generator/commands"

Kemalyst::Generator::MainCommand.run ARGV
