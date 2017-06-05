require "icr"
require "cli"
require "yaml"
require "colorize"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "r", aliased: "release"

    class Console < Cli::Command
      command_name "release"

      def run
        release
      end

      class Help
        caption "# Starts a Amber console"
      end

      class Options
        arg "version", desc: "# New project version Eg. 1.2.0", required: true
        arg "msg", desc: "# Short release description", required: true
      end

      def deploy(app)
        `heroku plugins:install heroku-docker`
        `heroku docker:start`
        `heroku docker:exec crystal deps && make`
        `heroku create "#{app}-amber"`
        `heroku docker:release`
        `heroku open`
      end

      def release
        new_version = args.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        name = shard["name"].to_s
        version = shard["version"].to_s

        files = {
            "shard.yml" => "version: #{version}",
            "src/#{name}/version.cr" => %Q(  VERSION = "#{version})
        }

        files.each do |filename, version_str|
            puts "Updating version numbers in #{filename}.".colorize(:light_magenta)
            file_string = File.read(filename).gsub(version_str, version_str.gsub(version, new_version))
            File.write(filename, file_string)
        end

        message = "Bumped version number to v#{new_version}." unless message = ARGV[1]?
        puts "git commit -am \"#{message}\"".colorize(:yellow)

        `git add .`
        `git commit -am "#{message}"`

        puts "git tag -a v#{new_version} -m \"#{name}: v#{new_version}\"".colorize(:yellow)

        `git tag -a v#{new_version} -m "#{name}: v#{new_version}"`

        puts "git push origin v#{new_version}".colorize(:yellow)
        `git push origin v#{new_version}`
        deploy(name)
      end
    end
  end
end
