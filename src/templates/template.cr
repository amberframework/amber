require "teeplate"
require "./app"
require "./scaffold"
require "./model"
require "./controller"
require "./migration"
require "./mailer"
require "./socket"
require "./channel"

module Amber::CMD
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

    def generate(template : String, options = nil)
      case template
      when "app"
        if options
          puts "Rendering App #{name} in #{directory}"
          App.new(name, options.d, options.t).render(directory, list: true, color: true)
          if options.deps?
            puts "Installing Dependencies"
            puts `cd #{name} && crystal deps update`
          end
        end
      when "scaffold"
        puts "Rendering Scaffold #{name}"
        Scaffold.new(name, fields).render(directory, list: true, color: true)
      when "model"
        puts "Rendering Model #{name}"
        Model.new(name, fields).render(directory, list: true, color: true)
      when "controller"
        puts "Rendering Controller #{name}"
        Controller.new(name, fields).render(directory, list: true, color: true)
      when "migration"
        puts "Rendering Migration #{name}"
        Migration.new(name, fields).render(directory, list: true, color: true)
      when "mailer"
        puts "Rendering Mailer #{name}"
        Mailer.new(name, fields).render(directory, list: true, color: true)
      when "socket"
        puts "Rendering Socket #{name}"
        if fields != [] of String
          fields.each do |field|
            WebSocketChannel.new(field).render(directory, list: true, color: true)
          end
        end
        WebSocket.new(name, fields).render(directory, list: true, color: true)
      when "channel"
        puts "Rendering Channel #{name}"
        WebSocketChannel.new(name).render(directory, list: true, color: true)
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
                      @data.path.gsub("+", "")
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
      renderer << filter(file_entries)
      renderer.render
      renderer
    end

    # Override to filter files rendered
    def filter(entries)
      entries
    end
  end
end
