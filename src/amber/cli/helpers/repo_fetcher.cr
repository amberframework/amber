require "http/client"
{% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
  require "compress/zip"
{% else %}
  require "zip"
{% end %}

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

      # the only other option is that name is a URL to a zip file
      if name && name.downcase.starts_with?("http") && name.downcase.ends_with?(".zip")
        return fetch_zip name, destination, kind
      end

      nil
    end

    def try_github(name : String)
      url = "https://raw.githubusercontent.com/#{name}/master/shard.yml"

      HTTP::Client.get(url) do |response|
        if response.status_code == 200
          return true
        end
        Log.error { "#{name} response #{url} #{response.status_code}".colorize(:light_red) }
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
          Log.error { "Couldn't parse #{filename} file".colorize(:light_red) }
          exit 1
        end
      else
        shard = RepoShard.new
      end

      shard.dependencies[shard_name] = {"github" => repo, "branch" => "master"}
      File.open(filename, "w") { |f| shard.to_yaml(f) }

      Log.info { "Installing shard".colorize(:light_cyan) }
      Amber::CLI::Helpers.run("cd #{destination} && shards update")
    end

    def fetch_zip(url : String, destination : String, kind : String)
      # download the recipe zip file from the github repository
      HTTP::Client.get(url) do |response|
        if response.status_code == 302
          # download the recipe zip file from redirected url
          if redirection_url = response.headers["Location"]?
            HTTP::Client.get(redirection_url) do |redirected_response|
              save_zip(redirected_response, destination, kind, url)
            end
          end
        elsif response.status_code != 200
          Log.error { "Could not download #{url} : #{response.status_code} #{response.status_message}".colorize(:light_red) }
          return nil
        end

        save_zip(response, destination, kind, url)
      end
    end

    def save_zip(response : HTTP::Client::Response, destination : String, kind : String, url : String)
      Dir.mkdir_p(destination)

      {% if compare_versions(Crystal::VERSION, "0.35.0-0") >= 0 %}
        Compress::Zip::Reader.open(response.body_io) do |zip|
          zip.each_entry do |entry|
            path = "#{destination}/#{entry.filename}"
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
            path = "#{destination}/#{entry.filename}"
            if entry.dir?
              Dir.mkdir_p(path)
            else
              File.write(path, entry.io.gets_to_end)
            end
          end
        end
      {% end %}

      if Dir.exists?("#{destination}/#{kind}")
        return "#{destination}/#{kind}"
      end

      # try an entry in the destination folder and check the entry is included in
      # the zip file url
      Dir.entries(destination).each do |entry|
        item = entry
        # a github release zip file has a version appended in the folder name
        # so take the first part as the entry name
        if entry.includes? "-"
          item = entry.split("-")[0]
        end

        if Dir.exists?("#{destination}/#{entry}/#{kind}") && url.includes? item
          return "#{destination}/#{entry}/#{kind}"
        end
      end

      nil
    end

  end
end