require "teeplate"
require "liquid"
require "base64"
require "./filters"

require "random/secure"
require "../helpers/helpers"

require "./file_entries"
require "./recipe_fetcher"
require "./app"
require "./controller"
require "./model"
require "./scaffold/controller"
require "./scaffold/view"

module Amber::Recipes
  AMBER_RECIPE_FOLDER = ENV["HOME"]+"/.amber/recipe_cache"

  class Recipe
    getter name : String
    getter directory : String
    getter recipe : String | Nil

    def self.can_generate?(template_type, recipe)
      return false unless ["app", "controller", "model", "scaffold" ].includes? template_type

      if recipe.nil?
        return false
      end

      template = RecipeFetcher.new(template_type, recipe).fetch
      template.nil? ? false : true
    end

    def initialize(name : String, directory : String, recipe : String, fields = [] of String)
      if name.match(/\A[a-zA-Z]/)
        @name = name.underscore
      else
        raise "Name is not valid."
      end

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end

      @recipe = recipe

      @fields = fields
    end

    def generate(template : String, options = nil)
      case template
      when "app"
        if options
          log_message "Rendering App #{name} in #{directory} from #{options.r}"
          App.new(name, options.d, options.t, options.m, options.r).render(directory, list: true, color: true)
          if options.deps?
            log_message "Installing Dependencies"
            Amber::CLI::Helpers.run("cd #{name} && shards update")
          end
        end
      when "controller"
        log_message "Rendering Controller #{name} from #{@recipe}"
        Controller.new(name, @recipe, @fields).render(directory, list: true, color: true)
      when "model"
        log_message "Rendering Model #{name} from #{@recipe}"
        Model.new(name, @recipe, @fields).render(directory, list: true, color: true)
      when "scaffold"
        log_message "Rendering Scaffold #{name} from #{@recipe}"
        if model == "crecto"
          Amber::CLI::CrectoMigration.new(name, @fields).render(directory, list: true, color: true)
        else
          Amber::CLI::GraniteMigration.new(name, @fields).render(directory, list: true, color: true)
        end
        Model.new(name, @recipe, @fields).render(directory, list: true, color: true)
        Scaffold::Controller.new(name, @recipe, @fields).render(directory, list: true, color: true)
        Scaffold::View.new(name, @recipe, @fields).render(directory, list: true, color: true)
      else
        CLI.logger.error "Template not found", "Generate", :light_red
      end
    end

    def model
      CLI.config.model
    end

    def log_message(msg)
      CLI.logger.info msg, "Generate", :light_cyan
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
      @class_name ||= @name.camelcase
    end

    def display_name
      @display_name ||= generate_display_name
    end

    private def generate_display_name
      @name.underscore.gsub('-', '_').split('_').map(&.capitalize).join(' ')
    end
  end
end
