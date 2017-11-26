require "cli"
require "./cli/commands"
require "./version"
Amber::CLI::MainCommand.run ARGV

module Amber
  ENCRYPTION_KEY = ENV["AMBER_SECRET_KEY"]? || begin
    if File.exists?(".amber_secret_key")
      File.open(".amber_secret_key").gets_to_end.to_s
    else
      nil 
    end
  end
end
