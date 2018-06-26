require "http/client"
require "zip"

module Amber::Recipes
  class RecipeFetcher
    getter kind : String # one of the supported kinds [app, controller, scaffold]
    getter name : String | Nil
    getter directory : String
    getter template_path : String

    def initialize(@kind : String, @name : String | Nil)
      @directory = "#{Dir.current}/#{@name}/#{@kind}"
      @template_path = "#{AMBER_RECIPE_FOLDER}/#{@name}"
    end

    def fetch
      if Dir.exists?(@directory)
        return @directory
      end

      if Dir.exists?("#{@name}/#{@kind}")
        return "#{@name}/#{@kind}"
      end

      if Dir.exists?("#{@template_path}/#{@kind}")
        return "#{@template_path}/#{@kind}"
      end

      if (name = @name) && name.downcase.starts_with?("http") && name.downcase.ends_with?(".zip")
        return fetch_zip name
      end

      return fetch_url
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
          CLI.logger.error "Could not find the recipe #{@name} : #{response.status_code} #{response.status_message}", "Generate", :light_red
          return nil
        end

        save_zip(response)
      end
    end

    def save_zip(response : HTTP::Client::Response)
      # make a temp directory and expand the zip into the temp directory
      Dir.mkdir_p(@template_path)

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

      # return the path of the template directory
      if Dir.exists?("#{@template_path}/#{@kind}")
        return "#{@template_path}/#{@kind}"
      end

      CLI.logger.error "Cannot generate #{@kind} from #{@name} recipe", "Generate", :light_red
      return nil
    end

    def fetch_url
      return fetch_zip "#{recipe_source}/#{@name}.zip"
    end
  end
end
