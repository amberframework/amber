require "../helpers/repo_fetcher"

module Amber::Plugins
  class PluginFetcher
    Log = ::Log.for(self)
    include Amber::Helpers::RepoFetcher

    getter kind : String = "plugin"
    getter name : String
    getter directory : String

    def initialize(name : String)
      if name.index('/') == nil
        @name = "amberplugin/#{name}" # a plugin in github/amberplugin organisation
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

      template = fetch_template(zip_folder, @name, @kind)
      Log.error { "Cannot generate plugin from #{name}".colorize(:light_red) } unless template
      template
    end

    def shard_folder(shard_name)
      "./.plugins/lib/#{shard_name}/#{@kind}"
    end

    def zip_folder
      "./.plugins/zip/#{@name}"
    end
  end
end
