require "teeplate"
require "liquid"
require "base64"

require "random/secure"
require "../helpers/helpers"
require "./file_entries"
require "./recipe_fetcher"
require "./app"
require "./controller"

module Amber::Recipes
  AMBER_RECIPE_FOLDER = "./.amber_recipe_cache"

  class Recipe
    getter name : String
    getter directory : String
    getter recipe : String

    def self.can_generate?(template_type, recipe)
      return false unless ["app", "controller" ].includes? template_type

      template = RecipeFetcher.new(template_type, recipe).fetch
      template.nil? ? false : true
    rescue
      p "Cannot generate a #{template_type} from #{recipe}"
      false
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

    def cleanup
      # if we used a template from github then remove the temp folder
      # this should probably be called as a command so templates are cached
      FileUtils.rm_rf(AMBER_RECIPE_FOLDER)
    end

    def generate(template : String, options = nil)
      case template
      when "app"
        if options
          puts "Rendering App #{name} in #{directory} from #{options.r}"
          App.new(name, options.d, options.t, options.m, options.r).render(directory, list: true, color: true)
          if options.deps?
            puts "Installing Dependencies"
            Amber::CLI::Helpers.run("cd #{name} && shards update")
          end
        end
      when "controller"
        puts "Rendering Controller #{name} from #{@recipe}"
        Controller.new(name, @recipe, @fields).render(directory, list: true, color: true)
      else
        CLI.logger.error "Template not found", "Generate", :light_red
      end
    end

    def model
      CLI.config.model
    end

    def puts(msg)
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
