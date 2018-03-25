require "http/client"
require "zip"

module Amber::Recipes
  class RecipeFetcher
    getter kind : String
    getter name : String
    getter directory : String

    def initialize(@kind : String, @name : String)
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
    end

    def fetch
      # if the recipe exists in the local recipes folder then use that
      if Dir.exists?(@directory)
        return @directory
      end

      # if the given recipe name is a directory and has a sub directory
      # for the kind of component being generated then use it
      if Dir.exists?("#{@name}/#{@kind}")
        return "#{@name}/#{@kind}"
      end

      # check the cached templates folder
      template_path = "#{AMBER_RECIPE_FOLDER}/#{@name}"

      if Dir.exists?("#{template_path}/#{@kind}")
        return "#{template_path}/#{@kind}"
      end

      # otherwise fetch from the github repository
      return fetch_url template_path
    end

    def fetch_url(template_path)
      # download the recipe zip file from the github repository
      HTTP::Client.get("https://raw.githubusercontent.com/AmberRecipes/recipes/master/#{@name}.zip") do |response|
        if response.status_code != 200
          # raise an exception if the recipe zip was not found
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

      # Log an error as the recipe does not contain the generator for
      # the kind of component being generated
      CLI.logger.error "Cannot generate #{@kind} from #{@name} recipe", "Generate", :light_red
      return nil
    end
  end
end
