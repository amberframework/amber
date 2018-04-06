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

      return fetch_url template_path
    end

    def recipe_source
      CLI.config.recipe_source || "https://raw.githubusercontent.com/amberframework/recipes/master/"
    end

    def fetch_url(template_path)
      # download the recipe zip file from the github repository
      HTTP::Client.get("#{recipe_source}/#{@name}.zip") do |response|
        if response.status_code != 200
          CLI.logger.error "Could not find that recipe #{@name}", "Generate", :light_red
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
  end
end
