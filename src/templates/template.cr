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
        App.new(name, @database, @language).render(directory, list: true, color: true)
      when "scaffold"
        puts "Rendering Scaffold #{name}"
        Scaffold.new(name, fields).render(directory, list: true, color: true)
      when "model"
        puts "Rendering Model #{name}"
        Model.new(name, fields).render(directory, list: true, color: true)
      when "controller"
        puts "Rendering Controller #{name}"
        Controller.new(name, fields).render(directory, list: true, color: true)
      when "mailer"
        puts "Rendering Mailer #{name}"
        Mailer.new(name, fields).render(directory, list: true, color: true)
      when "migration"
        puts "Rendering Migration #{name}"
        Migration.new(name, fields).render(directory, list: true, color: true)
      else
        raise "Template not found"
      end
    end
  end
end

class Teeplate::RenderingEntry
  def appends?
    @data.path.includes?("+")
  end

  def forces?
    appends? || @data.forces? || @renderer.forces?
  end

  def local_path
    @local_path ||= if appends?
      @data.path.gsub("+","")
    else
      @data.path
    end
  end
end

module Teeplate
  abstract class FileTree
    # Renders all collected file entries.
    #
    # For more information about the arguments, see `Renderer`.
    def render(out_dir, force : Bool = false, interactive : Bool = false, interact : Bool = false, list : Bool = false, color : Bool = false, per_entry : Bool = false, quit : Bool = true)
      renderer = Renderer.new(out_dir, force: force, interact: interactive || interact, list: list, color: color, per_entry: per_entry, quit: quit)
      entries = file_entries.reject{|entry| filter(entry) }
      renderer << entries
      renderer.render
      renderer
    end

    # Override to filter files based on filename
    def filter(entry)
      return false
    end
  end
end

