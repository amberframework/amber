require "teeplate"
require "random/secure"
require "inflector"

require "./helpers/helpers"
require "./generators/**"

module Amber::CLI
  class Generators
    getter name : String
    getter directory : String
    getter fields : Array(String)

    def initialize(name : String, directory : String, fields = [] of String)
      if name.match(/\A[a-zA-Z]/)
        @name = name.underscore
      else
        error "Name is not valid."
        exit 1
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
          info "Rendering App #{name} in #{directory}"
          App.new(name, options.d, options.t, options.m).render(directory)
          unless options.no_deps?
            info "Installing Dependencies"
            Helpers.run("cd #{directory} && shards update")
          end
        end
      when "migration"
        info "Rendering Migration #{name}"
        Migration.new(name, fields).render(directory)
      when "model"
        info "Rendering Model #{name}"
        Model.new(name, fields).render(directory)
      when "controller"
        info "Rendering Controller #{name}"
        Controller.new(name, fields).render(directory)
      when "scaffold"
        info "Rendering Scaffold #{name}"
        Scaffold.new(name, fields).render(directory)
      when "api"
        info "Rendering Api #{name}"
        Api.new(name, fields).render(directory)
      when "mailer"
        info "Rendering Mailer #{name}"
        Mailer.new(name, fields).render(directory)
      when "socket"
        info "Rendering Socket #{name}"
        WebSocket.new(name, fields).render(directory)
      when "channel"
        info "Rendering Channel #{name}"
        WebSocketChannel.new(name, fields).render(directory)
      when "auth"
        info "Rendering Auth #{name}"
        if model == "crecto"
          CrectoAuth.new(name, fields).render(directory)
        else
          GraniteAuth.new(name, fields).render(directory)
        end
      when "error"
        info "Rendering Error Template"
        ErrorTemplate.new("error", fields).render(directory)
      else
        CLI.logger.error "Template not found", "Generate", :light_red
      end
    end

    def model
      CLI.config.model
    end

    def info(msg)
      CLI.logger.info msg, "Generate", :light_cyan
    end

    def error(msg)
      CLI.logger.error msg, "Generate", :red
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

  def list(s, color)
    Amber::CLI.logger.info s.colorize.fore(color).to_s + local_path, "Generate", :light_cyan
  end
end

module Teeplate
  abstract class FileTree
    @name_plural : String?
    @class_name : String?
    @display_name : String?
    @display_name_plural : String?

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

    def name_plural
      @name_plural ||= Inflector.pluralize(@name)
    end

    def class_name
      @class_name ||= @name.camelcase
    end

    def display_name
      @display_name ||= generate_display_name
    end

    def display_name_plural
      @display_name_plural ||= Inflector.pluralize(display_name)
    end

    private def generate_display_name
      @name.underscore.gsub('-', '_').split('_').map(&.capitalize).join(' ')
    end
  end
end
