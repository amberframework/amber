require "teeplate"
require "./app"
require "./resource"

module Kemalyst::Generator
  class Template
    getter name : String
    getter directory : String

    def initialize(name : String, directory : String)
      if name.match(/\A[a-zA-Z]/)
        @name = name
      else
        raise "Name is not valid."
      end

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end
    end

    def generate(template : String)
      case template
      when "app"
        puts "Rendering App #{name} in #{directory}"
        App.new(name).render(directory)
      when "resource"
        puts "Rendering Resource #{name} in #{directory}"
        Resource.new(name).render(directory)
      else
        raise "Template not found"
      end
    end
  end
end
