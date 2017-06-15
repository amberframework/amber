require "icr"
require "cli"
require "yaml"
require "colorize"

module Amber::CMD
  class MainCommand < Cli::Supercommand
    command "r", aliased: "release"

    class Release < Cli::Command
      command_name "release"

      def run
        release
      end

      class Help
        caption "# Creates mark release points and deploy to cloud services"
        title "\nAmber - Release Command"
        header <<-EOS
          The `amber release` allows for you to mark and tag releases safely and
          deploy to cloud services.

          * Amazon Web Services \t* Microsoft Azure       * Digital Ocean
          * Exoscale            \t* Google Compute Engine * Generic
          * Microsoft Hyper-V   \t* OpenStack             * Rackspace
          * IBM Softlayer       \t* Oracle VirtualBox     * VMware vCloud Air
          * VMware Fusion       \t* VMware vSphere

          Your must specify the cloud service config in your `.amber.yml` project
          file.

            digitalocean:
              access-token: accesstokenhere
              image: ubuntu-16-04-x64
              private-networking: true
              size: 2gb

            amazonec2:
              ami: ami-5f709f34
              region: us-east-1
              zone: a

          NOTE:
            - You must have git, docker, docker-machine and docker-compose installed
            - Your project must contain a valid dockerfile.
            To learn how to configure your docker-machine read https://docs.docker.com/machine/drivers/

          Usage:
            amber release -v [version] [commit message] -d [digitalocean | amazonec2]
          EOS

        footer <<-EOS
        Example:
          amber release -v 1.2.3 -d digitalocean
        EOS
      end

      class Options
        help
        string %w(-v --version), desc: "# New project version Eg. 1.2.0", required: true
        arg "msg", desc: "# Short release description", required: true
        string %w(-d --deploy), desc: "# Deploy to cloud service: digitalocean | heroku | aws | azure"
      end

      def cloud_deploy(app_name, driver, current_version)
        app = "#{app_name}-#{current_version}"
        show "Deploying #{app}", :yellow
        driver_command = Docker::Machine::Command.build(driver, "./.amber.yml")
        `docker-machine create #{app} #{driver_command}`
        `docker-machine env #{app}`
      end

      def release
        new_version = options.version
        message = args.msg
        shard = YAML.parse(File.read("./shard.yml"))
        name = shard["name"].to_s
        version = shard["version"].to_s
        driver = options.d

        show "Your are about to make a release:"
        show "Current Version #{version.colorize(:yellow)}"
        show "Release Version #{new_version.colorize(:yellow)}"
        ask "Continue? (y|N)" { bump_version(name, version, new_version) }

        show "You are about to tag a release #{new_version}"
        ask "Continue? (y|N)" { create_tag(name, message, new_version) }

        show "Bumped version number to v#{new_version.colorize(:green)}.", :green
        show "App (#{name}-#{new_version}) released and pushed to github.", :green
        puts

        show "You are about to deploy to #{options.d.colorize(:yellow)}."
        ask "Continue? (y|N)" { cloud_deploy(name, driver, new_version) }
        show "Deploy complete! #{name}", :green
        puts
      end

      def bump_version(name, current_version, new_version)
        files = {
          "shard.yml"              => "version: #{current_version}",
          "src/#{name}/version.cr" => %Q(  VERSION = "#{current_version}),
        }

        files.each do |filename, version_str|
          file_string = File.read(filename).gsub(version_str, version_str.gsub(current_version, new_version))
          File.write(filename, file_string)
          show "Version number updated in #{filename}.", :green
        end
      end

      def create_tag(name, message, new_version)
        `git checkout master`
        `git add .`
        `git commit -am "#{message}"`
        `git push -f`
        `git tag -a v#{new_version} -m "#{name}: v#{new_version}"`
        `git push origin v#{new_version}`
      end

      def show(msg, color = :dark_gray)
        puts "#{msg}".colorize(color)
      end

      def ask(question : String, &block)
        show question
        continue = gets.not_nil!.strip
        if %w(Y y).includes? continue
          puts "\n"
          block.call
          puts "\n"
        else
          show "Good bye :("
          exit 1
        end
      end
    end
  end
end
