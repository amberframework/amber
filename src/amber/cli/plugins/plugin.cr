require "teeplate"
require "liquid"
require "base64"

require "random/secure"
require "../helpers/helpers"

require "../recipes/file_entries"
require "./plugin_fetcher"
require "./installer"

module Amber::Plugins

  class Plugin
    getter name : String
    getter directory : String

    def self.can_generate?(name : String)
      if name.nil?
        return false
      end

      template = PluginFetcher.new(name).fetch
      template.nil? ? false : true
    end

    def initialize(name : String, directory : String)
      @name = name

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end
    end

    def generate(action : String, options = nil)
      case action
      when "add"
     
        log_message "Adding plugin #{name}"
        PluginInstaller.new(name).render(directory, list: true, color: true)
      when "migrate"

      when "rollback"
      else
        CLI.logger.error "Invalid plugin command", "Plugin", :light_red
      end
    end

    def log_message(msg)
      CLI.logger.info msg, "Plugin", :light_cyan
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
