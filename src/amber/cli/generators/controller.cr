require "file_utils"

module Amber::CLI
  class Controller < Generator
    directory "#{__DIR__}/../templates/controller"

    property actions : Hash(String, String)

    def initialize(name, params)
      super(name, nil)
      @actions = parse_actions(params)
    end

    def pre_render(directory)
      add_routes
      add_views
    end

    private def parse_actions(params)
      actions = Hash(String, String).new
      params.each do |action|
        next unless action.size > 0
        split_action = action.split(":")
        actions[split_action.first] = split_action[1]? || "get"
      end
      actions
    end

    private def add_routes
      add_routes :web, <<-ROUTES
        #{@actions.map { |action, verb| %Q(#{verb} "/#{@name}/#{action}", #{class_name}Controller, :#{action}) }.join("\n    ")}
      ROUTES
    end

    private def add_views
      @actions.each do |action_name, _|
        FileUtils.mkdir_p("src/views/#{@name}")
        File.touch("src/views/#{@name}/#{action_name}.#{config.language}")
      end
    end
  end
end
