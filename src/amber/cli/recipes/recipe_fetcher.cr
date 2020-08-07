require "http/client"
{% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
  require "compress/zip"
{% else %}
  require "zip"
{% end %}

module Amber::Recipes
  class RecipeFetcher
    Log = ::Log.for(self)

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

        if @kind == "app" && try_github
          fetch_github shard_name
          path = "#{recipes_folder}/lib/#{shard_name}/#{@kind}"
          return path if Dir.exists?(path)
        end
      end

      @template_path = "#{recipes_folder}/zip/#{@name}"
      fetch_template(recipes_folder, @name)
    end

    def fetch_template(template_path, name)
      path = "#{template_path}/#{@kind}"
      return path if Dir.exists?(path)

      if name && name.downcase.starts_with?("http") && name.downcase.ends_with?(".zip")
        return fetch_zip name
      end

      fetch_url
    end

    def recipes
      @kind == "app" ? "#{app_dir}/.recipes" : "./.recipes"
    end

    def try_github
      url = "https://raw.githubusercontent.com/#{@name}/master/shard.yml"

      HTTP::Client.get(url) do |response|
        if response.status_code == 200
          return true
        end
      end
      false
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

    def recipe_source
      CLI.config.recipe_source || "https://github.com/amberframework/recipes/releases/download/dist/"
    end

    def fetch_zip(url : String)
      # download the recipe zip file from the github repository
      HTTP::Client.get(url) do |response|
        if response.status_code == 302
          # download the recipe zip frile from redirected url
          if redirection_url = response.headers["Location"]?
            HTTP::Client.get(redirection_url) do |redirected_response|
              save_zip(redirected_response)
            end
          end
        elsif response.status_code != 200
          Log.error { "Could not find the recipe #{@name} : #{response.status_code} #{response.status_message}".colorize(:light_red) }
          return nil
        end

        save_zip(response)
      end
    end

    def save_zip(response : HTTP::Client::Response)
      Dir.mkdir_p(@template_path)

      {% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
        Compress::Zip::Reader.open(response.body_io) do |zip|
          zip.each_entry do |entry|
            path = "#{@template_path}/#{entry.filename}"
            if entry.dir?
              Dir.mkdir_p(path)
            else
              File.write(path, entry.io.gets_to_end)
            end
          end
        end
      {% else %}
        Zip::Reader.open(response.body_io) do |zip|
          zip.each_entry do |entry|
            path = "#{@template_path}/#{entry.filename}"
            if entry.dir?
              Dir.mkdir_p(path)
            else
              File.write(path, entry.io.gets_to_end)
            end
          end
        end
      {% end %}

      if Dir.exists?("#{@template_path}/#{@kind}")
        return "#{@template_path}/#{@kind}"
      end

      Log.error { "Cannot generate #{@kind} from #{@name} recipe".colorize(:light_red) }
      nil
    end

    def fetch_url
      fetch_zip "#{recipe_source}/#{@name}.zip"
    end
  end
end
