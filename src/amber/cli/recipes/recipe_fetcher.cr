require "http/client"
require "zip"

module Amber::Recipes
  class RecipeFetcher
    getter kind : String
    getter name : String
    getter directory : String

    def initialize(@kind : String, @name : String)
      @directory = "#{__DIR__}/#{@kind}/#{@name}"
    end

    def fetch
      # if the recipe exists in the local recipes folder then use that
      if Dir.exists?(@directory)
        return @directory
      end

      # if the given recipe name is a directory then use it
      if Dir.exists?(@name)
        return @name
      end

      # otherwise fetch from the github repository
      return fetch_url
    end

    def fetch_url
      # download the recipe zip file from the github repository
      HTTP::Client.get("https://raw.githubusercontent.com/AmberRecipes/recipes/master/#{@kind}/#{@name}.zip") do |response|
        if response.status_code != 200
          # raise an exception if the recipe zip was not found
          raise "Could not find that recipe"
        end

        # ensure the temp folder does not exist
        FileUtils.rm_rf(TEMP_RECIPE_FOLDER)

        # make a temp directory and expand the zip into the temp directory
        Dir.mkdir_p(TEMP_RECIPE_FOLDER)

        Zip::Reader.open(response.body_io) do |zip|
          zip.each_entry do |entry|
            path = "#{TEMP_RECIPE_FOLDER}/#{entry.filename}"
            if entry.dir?
              Dir.mkdir_p(path)
            else
              File.write(path, entry.io.gets_to_end)
            end
          end
        end
      end

      # return the path of the temp directory
      TEMP_RECIPE_FOLDER
    end
  end
end
