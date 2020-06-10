require "log"
require "cli"
require "./version"
require "./exceptions/*"
require "./environment"
require "./cli/commands"

backend = Log::IOBackend.new
backend.formatter = Log::Formatter.new do |entry, io|
  io << entry.timestamp.to_s("%I:%M:%S")
  io << " "
  io << entry.source
  io << " (#{entry.severity})" if entry.severity > Log::Severity::Debug
  io << " "
  io << entry.message
end
Log.builder.bind "*", :info, backend

Amber::CLI::MainCommand.run ARGV
