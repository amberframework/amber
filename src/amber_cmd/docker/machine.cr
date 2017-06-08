require "yaml"

module Amber::CMD
  # Docker Machine is a tool that lets you install Docker Engine on virtual hosts,
  # and manage the hosts with docker-machine commands. You can use Machine to create
  # Docker hosts on your local Mac or Windows box, on your company network, in
  # your data center, or on cloud providers like Azure, AWS, or Digital Ocean.

  # Using docker-machine commands, you can start, inspect, stop, and restart a managed host,
  # upgrade the Docker client and daemon, and configure a Docker client to talk to your host.
  module Docker::Machine
    # Builds the driver part of the Docker Machine driver command used for the
    # deploy flag in releases
    class Command
      private getter driver : String
      private getter config

      def self.build(driver, yml_file)
        new(driver, yml_file).build
      end

      def initialize(@driver, file)
        @config = YAML.parse(File.read(file))
      end

      def build
        cmd = "--driver #{driver}"
        config[@driver].each do |key, val|
          cmd += " --#{driver}-#{key}=#{val}"
        end
        cmd
      end
    end
  end
end
