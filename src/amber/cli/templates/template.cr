require "teeplate"
require "random/secure"
require "../helpers/helpers"
require "./app"
require "./migration"
require "./crecto_migration"
require "./granite_migration"
require "./jennifer_migration"
require "./model"
require "./crecto_model"
require "./granite_model"
require "./controller"
require "./scaffold/crecto_controller"
require "./scaffold/granite_controller"
require "./scaffold/view"
require "./mailer"
require "./socket"
require "./channel"
require "./crecto_auth"
require "./granite_auth"
require "./jennifer_auth"
require "./error"
require "./sam"

module Amber::CLI
  class Template
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
        info "Rendering App #{name} in #{directory}"
        generate_app(options)
      when "migration"
        info "Rendering Migration #{name}"
        generate_migration
      when "model"
        info "Rendering Model #{name}"
        if model == "crecto"
          CrectoMigration.new(name, fields).render(directory, list: true, color: true)
          CrectoModel.new(name, fields).render(directory, list: true, color: true)
        else
          GraniteMigration.new(name, fields).render(directory, list: true, color: true)
          GraniteModel.new(name, fields).render(directory, list: true, color: true)
        end
      when "controller"
        info "Rendering Controller #{name}"
        Controller.new(name, fields).render(directory, list: true, color: true)
      when "scaffold"
        info "Rendering Scaffold #{name}"
        if model == "crecto"
          CrectoMigration.new(name, fields).render(directory, list: true, color: true)
          CrectoModel.new(name, fields).render(directory, list: true, color: true)
          Scaffold::CrectoController.new(name, fields).render(directory, list: true, color: true)
        else
          GraniteMigration.new(name, fields).render(directory, list: true, color: true)
          GraniteModel.new(name, fields).render(directory, list: true, color: true)
          Scaffold::GraniteController.new(name, fields).render(directory, list: true, color: true)
        end
        Scaffold::View.new(name, fields).render(directory, list: true, color: true)
      when "mailer"
        info "Rendering Mailer #{name}"
        Mailer.new(name, fields).render(directory, list: true, color: true)
      when "socket"
        info "Rendering Socket #{name}"
        if fields != [] of String
          fields.each do |field|
            WebSocketChannel.new(field).render(directory, list: true, color: true)
          end
        end
        WebSocket.new(name, fields).render(directory, list: true, color: true)
      when "channel"
        info "Rendering Channel #{name}"
        WebSocketChannel.new(name).render(directory, list: true, color: true)
      when "auth"
        info "Rendering Auth #{name}"
        generate_authentication
      when "error"
        info "Rendering Error Template"
        actions = ["forbidden", "not_found", "internal_server_error"]
        ErrorTemplate.new("error", actions).render(directory, list: true, color: true)
      when "sam"
        generate_sam
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

    def migration
      CLI.config.migration
    end

    private def generate_authentication
      case model
      when "crecto"
        CrectoAuth.new(name, fields).render(directory, list: true, color: true)
      when "jennifer"
        JenniferAuth.new(name, fields).render(directory, list: true, color: true)
      else
        GraniteAuth.new(name, fields).render(directory, list: true, color: true)
      end
    end

    private def generate_app(options)
      return unless options
      info "Rendering App #{name} in #{directory}"
      App.new(name, options.d, options.t, options.m, options.sam?).render(directory, list: true, color: true)
      generate_sam if options.sam?
      if options.deps?
        info "Installing Dependencies"
        Helpers.run("cd #{name} && shards update")
      end
    end

    private def generate_sam(options = nil)
      if File.exists?(File.join(directory, MainCommand::Sam::SAM_PATH))
        info "Sam file is already exists."
      else
        info "Rendering Sam file"
        Sam.new(options.try(&.m) || model).render(directory, list: true, color: true)
      end
    end

    def generate_migration(migration_name = name)
      migration_instance =
        if model == "jennifer" && migration == "jennifer"
          Jennifer::Migration.build(migration_name, fields)
        else
          Migration.new(migration_name, fields)
        end
      migration_instance.render(directory, list: true, color: true)
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
    @class_name : String?
    @display_name : String?

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

    def class_name
      @class_name ||= Inflector.classify(@name)
    end

    def display_name
      @display_name ||= generate_display_name
    end

    private def generate_display_name
      @name.underscore.gsub('-', '_').split('_').map(&.capitalize).join(' ')
    end
  end
end
