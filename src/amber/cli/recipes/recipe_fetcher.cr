require "http/client"
{% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
  require "compress/zip"
{% else %}
  require "zip"
{% end %}

require "../helpers/repo_fetcher"

module Amber::Recipes
  class RecipeFetcher
    Log = ::Log.for(self)
    include Amber::Helpers::RepoFetcher

    getter kind : String # one of the supported kinds [app, model, controller, scaffold]
    getter name : String
    getter directory : String
    getter app_dir : String | Nil
    getter template_path : String

    def initialize(@kind : String, @name : String, @app_dir = nil)
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
      @template_path = "#{Dir.current}/.recipes/zip/#{@name}"
    end

    def fetch
      return @directory if Dir.exists?(@directory)
      return "#{@name}/#{@kind}" if Dir.exists?("#{@name}/#{@kind}")

      parts, recipes_folder = @name.split("/"), recipes

      if parts.size == 2 && (shard_name = parts[-1])
        if @kind != "app"
          path = "#{recipes_folder}/lib/#{shard_name}/#{@kind}"
          return Dir.exists?(path) ? path : nil
        end

        if @kind == "app" && try_github(@name)
          fetch_repo_shard(@name, "#{app_dir}/.recipes")
          path = "#{recipes_folder}/lib/#{shard_name}/#{@kind}"
          return path if Dir.exists?(path)
        end
      end

      template = fetch_template(recipes_folder, @name, @kind)
      Log.error { "Cannot generate #{kind} from #{name} recipe".colorize(:light_red) } unless template
      template
    end

    def recipes
      @kind == "app" ? "#{app_dir}/.recipes" : "./.recipes"
    end

    def create_recipe_shard(shard_name)
      dirname = "#{app_dir}/.recipes"
      Dir.mkdir_p(dirname)
      filename = "#{dirname}/shard.yml"

      yaml = {name: "recipe", version: "0.1.0", dependencies: {shard_name => {github: @name, branch: "master"}}}

      Log.info { "Create Recipe shard #{filename}".colorize(:light_cyan) }
      File.open(filename, "w") { |f| yaml.to_yaml(f) }
    end

    def fetch_github(shard_name)
      create_recipe_shard shard_name

      Log.info { "Installing Recipe".colorize(:light_cyan) }
      Amber::CLI::Helpers.run("cd #{app_dir}/.recipes && shards update")
    end
  end
end
