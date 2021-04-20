require "./spec_helper"
require "./support/helpers/cli_helper"

include CLIHelper

module Amber::CLI
  extend self

  def generate_app(*options)
    ENV["AMBER_ENV"] = "test"

    cleanup
    scaffold_app(TESTING_APP, *options)
    system("shards install --ignore-crystal-version")
    options = ["user:reference", "name:string", "body:text", "age:integer", "published:bool"]
    temp_options = options - ["user:reference", "age:integer"]
    MainCommand.run ["generate", "auth", "-y", "User"] | (options - ["user:reference"])
    MainCommand.run ["generate", "error", "-y", "ErrorPage"]
    MainCommand.run ["generate", "scaffold", "-y", "Animal"] | temp_options
    MainCommand.run ["generate", "scaffold", "-y", "Post"] | options
    MainCommand.run ["generate", "scaffold", "-y", "PostComment"] | (options + ["post:reference"])
    MainCommand.run ["generate", "model", "-y", "Bat"] | options
    MainCommand.run ["generate", "migration", "-y", "Crocodile"] | options
    MainCommand.run ["generate", "mailer", "-y", "EmptyMailer"]
    MainCommand.run ["generate", "mailer", "-y", "Dinosaur"] | options
    MainCommand.run ["generate", "socket", "-y", "Eagle"] | ["soar", "nest"]
    MainCommand.run ["generate", "channel", "-y", "Falcon"]
    MainCommand.run ["generate", "api", "-y", "MyApi"]
    MainCommand.run ["generate", "api", "-y", "MyApiWithParams"] | options
    MainCommand.run ["generate", "controller", "-y", "ControllerWithoutParams"]
    MainCommand.run ["generate", "controller", "-y", "MyController", "myview"]

    prepare_yaml(Dir.current)
    Amber::CLI.env = "test"
    MainCommand.run ["db", "drop", "create", "migrate"]
  end
end
