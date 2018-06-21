require "./spec_helper"
require "./support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  extend self

  def generate_app(*options)
    ENV["AMBER_ENV"] = "test"

    cleanup
    scaffold_app(TESTING_APP, *options)

    options = ["user:reference", "name:string", "body:text", "age:integer", "published:bool"]
    temp_options = options - ["user:reference", "age:integer"]
    MainCommand.run ["generate", "auth", "User"] | (options - ["user:reference"])
    MainCommand.run ["generate", "error"]
    MainCommand.run ["generate", "scaffold", "Animal"] | temp_options
    MainCommand.run ["generate", "scaffold", "Post"] | options
    MainCommand.run ["generate", "scaffold", "PostComment"] | (options + ["post:reference"])
    MainCommand.run ["generate", "model", "Bat"] | options
    MainCommand.run ["generate", "migration", "Crocodile"] | options
    MainCommand.run ["generate", "mailer", "Dinosaur"] | options
    MainCommand.run ["generate", "socket", "Eagle"] | ["soar", "nest"]
    MainCommand.run ["generate", "channel", "Falcon"]

    prepare_yaml(Dir.current)
    Amber::CLI.env = "test"
    Amber::CLI.settings.logger = Amber::Environment::Logger.new(nil)
    MainCommand.run ["db", "drop", "create", "migrate"]
  end
end
