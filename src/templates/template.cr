require "teeplate"
require "./app"
require "./scaffold"
require "./model"
require "./controller"
require "./mailer"
require "./migration"

module Kemalyst::Generator
  class Template
    getter name : String
    getter directory : String
    getter fields : Array(String)
    getter database : String
    getter language : String

    def initialize(name : String, directory : String, fields = [] of String, database = "pg", language = "slang")
      if name.match(/\A[a-zA-Z]/)
        @name = name
      else
        raise "Name is not valid."
      end

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end

      @fields = fields
      @database = database
      @language = language
    end

    def generate(template : String)
      case template
      when "app"
        puts "Rendering App #{name} in #{directory}"
        App.new(name, @database, @language).render(directory)
      when "scaffold"
        puts "Rendering Scaffold #{name}"
        Scaffold.new(name, fields).render(directory)
      when "model"
        puts "Rendering Model #{name}"
        Model.new(name, fields).render(directory)
      when "controller"
        puts "Rendering Controller #{name}"
        Controller.new(name, fields).render(directory)
      when "mailer"
        puts "Rendering Mailer #{name}"
        Mailer.new(name, fields).render(directory)
      when "migration"
        puts "Rendering Migration #{name}"
        Migration.new(name, fields).render(directory)
      else
        raise "Template not found"
      end
    end
  end
end
