require "http/client"
require "zip"

module Amber::Recipes
  class RecipeFetcher
    getter kind : String # one of the supported kinds [app, controller, scaffold]
    getter name : String | Nil
    getter directory : String

    def initialize(@kind : String, @name : String | Nil)
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
    end

    def fetch
      if Dir.exists?(@directory)
        return @directory
      end

      if Dir.exists?("#{@name}/#{@kind}")
        return "#{@name}/#{@kind}"
      end

      template_path = "#{AMBER_RECIPE_FOLDER}/#{@name}"

      if Dir.exists?("#{template_path}/#{@kind}")
        return "#{template_path}/#{@kind}"
      end

      if @name.not_nil!.downcase.starts_with?("http") && @name.not_nil!.downcase.ends_with?(".zip")
        return fetch_zip @name.as(String), template_path
      end

      return fetch_url template_path
    end

    def recipe_source
      CLI.config.recipe_source || "https://github.com/amberframework/recipes/releases/download/dist/"
    end

    def fetch_zip(url : String, template_path : String)
      # download the recipe zip file from the github repository
      HTTP::Client.get(url) do |response|
        if response.status_code != 200
          CLI.logger.error "Could not find the recipe #{@name} : #{response.status_code} #{response.status_message}", "Generate", :light_red
          return nil
        end

        # make a temp directory and expand the zip into the temp directory
        Dir.mkdir_p(template_path)

        Zip::Reader.open(response.body_io) do |zip|
          zip.each_entry do |entry|
            path = "#{template_path}/#{entry.filename}"
            if entry.dir?
              Dir.mkdir_p(path)
            else
              File.write(path, entry.io.gets_to_end)
            end
          end
        end
      end

      # return the path of the template directory
      if Dir.exists?("#{template_path}/#{@kind}")
        return "#{template_path}/#{@kind}"
      end

      CLI.logger.error "Cannot generate #{@kind} from #{@name} recipe", "Generate", :light_red
      return nil
    end

    def fetch_url(template_path : String)
      return fetch_zip "#{recipe_source}/#{@name}.zip", template_path
    end
  end
end
