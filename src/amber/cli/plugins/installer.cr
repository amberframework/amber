module Amber::Plugins
  class Installer < Teeplate::FileTree
    include Amber::CLI::Helpers
    include Amber::Recipes::FileEntries

    property template : String?

    property name : String
    getter language : String = CLI.config.language
    property timestamp : String

    def initialize(@name)
      @template = Fetcher.new(name).fetch
      @timestamp = Time.utc.to_s("%Y%m%d%H%M%S%L")
    end

    def render(directory, **args)
      pre_render(directory, **args)
      super(directory, **args)
    end

    def pre_render(directory, **args)
      add_routes
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "name", name
      ctx.set "language", language
      ctx.set "timestamp", timestamp
    end

    private def add_routes
      return unless File.exists?("#{template}/config.yml")

      config_file = File.read("#{template}/config.yml").to_s
      settings = Settings.from_yaml(config_file)

      settings.routes["pipelines"].each do |pipe, routes|
        add_routes pipe, routes.join("\n    ")
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
