require "http/client"
require "zip"

module Amber::Helpers
  module RepoFetcher

    class RepoShard

      alias Dependencies = Hash(String, Hash(String, String))

      property name : String = "repo"
      property version : String = "0.1.0"
      property dependencies : Dependencies

      def initialize
        @dependencies = Dependencies.new
      end

      YAML.mapping(
        name: {type: String, default: "repo"},
        version: {type: String, default: "0.1.0"},
        dependencies: {type: Dependencies, default: Dependencies.new },
      )
    end

    def fetch_template(destination : String, name : String, kind : String)
      path = "#{destination}/#{kind}"
      return path if Dir.exists?(path)

      if name && name.downcase.starts_with?("http") && name.downcase.ends_with?(".zip")
        return fetch_zip name, destination, kind
      end

      fetch_url name, destination, kind
    end

    def try_github(name : String)
      url = "https://raw.githubusercontent.com/#{name}/master/shard.yml"

      HTTP::Client.get(url) do |response|
        if response.status_code == 200
          return true
        end
      end
      false
    end

    def fetch_repo_shard(repo : String, destination : String)

      Dir.mkdir_p(destination)
      filename = "#{destination}/shard.yml"

      parts = repo.split("/")
      shard_name = parts[-1]

      if File.exists? filename
        begin
          shard = RepoShard.from_yaml File.read(filename)
        rescue ex : YAML::ParseException
          CLI.logger.error "Couldn't parse #{filename} file", "Watcher", :red
          exit 1
        end
      else
        shard = RepoShard.new
      end

      shard.dependencies[shard_name] = {"github" => repo, "branch" => "master"}
      File.open(filename, "w") { |f| shard.to_yaml(f) }

      CLI.logger.info "Installing shard", "Generate", :light_cyan
      Amber::CLI::Helpers.run("cd #{destination} && shards update")
    end

    def fetch_zip(url : String, destination : String, kind : String)
      # download the recipe zip file from the github repository
      HTTP::Client.get(url) do |response|
        if response.status_code == 302
          # download the recipe zip frile from redirected url
          if redirection_url = response.headers["Location"]?
            HTTP::Client.get(redirection_url) do |redirected_response|
              save_zip(redirected_response, destination, kind)
            end
          end
        elsif response.status_code != 200
          CLI.logger.error "Could not download #{url} : #{response.status_code} #{response.status_message}", "Generate", :light_red
          return nil
        end

        save_zip(response, destination, kind)
      end
    end

    def save_zip(response : HTTP::Client::Response, destination : String, kind : String)
      Dir.mkdir_p(destination)

      Zip::Reader.open(response.body_io) do |zip|
        zip.each_entry do |entry|
          path = "#{destination}/#{entry.filename}"
          if entry.dir?
            Dir.mkdir_p(path)
          else
            File.write(path, entry.io.gets_to_end)
          end
        end
      end

      if Dir.exists?("#{destination}/#{kind}")
        return "#{destination}/#{kind}"
      end

      nil
    end

    abstract def fetch_url(name, directory, kind)

  end
end