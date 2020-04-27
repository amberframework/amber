require "../helpers/repo_fetcher"

module Amber::Recipes
  class RecipeFetcher
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

      @template_path = "#{recipes_folder}/zip/#{@name}"
      fetch_template(recipes_folder, @name, @kind)
    end

    def recipes
      @kind == "app" ? "#{app_dir}/.recipes" : "./.recipes"
    end

    def recipe_source
      CLI.config.recipe_source || "https://github.com/amberframework/recipes/releases/download/dist/"
    end

    def fetch_url(name, directory, kind)
      template = fetch_zip "#{recipe_source}/#{name}.zip",  directory, kind
      CLI.logger.error "Cannot generate #{kind} from #{name} recipe", "Generate", :light_red unless template
      template
    end

  end
end
