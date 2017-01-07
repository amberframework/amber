require "teeplate"
require "./app"
require "./scaffold"

module Kemalyst::Generator
  class Template
    getter name : String
    getter directory : String
    getter fields : Array(String)

    def initialize(name : String, directory : String, fields = [] of String)
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
    end

    def generate(template : String)
      case template
      when "app"
        puts "Rendering App #{name} in #{directory}"
        App.new(name).render(directory)
      when "scaffold"
        puts "Rendering Scaffold #{name} in #{directory}"
        Scaffold.new(name, fields).render(directory)
      else
        raise "Template not found"
      end
    end
  end
end
