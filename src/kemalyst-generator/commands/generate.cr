require "crustache"

module Kemalyst::Generator

  class MainCommand < Cli::Supercommand
    command "g", aliased: "generate"
    
    class Generate < Cli::Command
      class Options
        arg "type", desc: "resource type: model, view, controller", required: true
        arg "name", desc: "Name of resource", required: true
      end

      def run
        puts "Todo: #{args.type} #{args.name}"
      end
    end
  end
end
