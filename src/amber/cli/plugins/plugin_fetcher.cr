require "../helpers/repo_fetcher"

module Amber::Plugins
  class PluginFetcher
    include Amber::Helpers::RepoFetcher

    getter kind : String = "plugin"
    getter name : String
    getter directory : String

    def initialize(name : String)
      if name.index('/') == nil
        @name = "amberplugin/#{name}"  # a plugin in github/amberplugin organisation 
      else
        @name = name
      end
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
    end

    def fetch
      return @directory if Dir.exists?(@directory)
      return "#{@name}/#{@kind}" if Dir.exists?("#{@name}/#{@kind}")

      parts = @name.split("/")

      if parts.size == 2 && (shard_name = parts[-1])
        path = shard_folder(shard_name)
        return path if Dir.exists?(path)

        if try_github(@name)
          fetch_repo_shard(@name, ".plugins")
          return path if Dir.exists?(path)
        end
      end

      fetch_template(zip_folder, @name, @kind)
    end

    def shard_folder(shard_name)
      "./.plugins/lib/#{shard_name}/#{@kind}"
    end

    def zip_folder
      "./.plugins/zip/#{@name}"
    end

    def repo_source
      CLI.config.recipe_source || "https://github.com/amberplugin/plugins/releases/download/dist/"
    end

    def fetch_url(name, directory, kind)
      template = fetch_zip "#{repo_source}/#{name}.zip",  directory, kind
      CLI.logger.error "Cannot generate plugin from #{name}", "Generate", :light_red unless template
      template
    end
  end
end