require "./field.cr"

module Amber::CLI
  class Controller < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/controller"
    private getter language

    @name : String
    @actions = Hash(String, String).new
    @language : String

    def initialize(@name, actions)
      @language = fetch_language
      parse_actions(actions)
      add_routes :web, <<-ROUTES
        #{@actions.map { |action, verb| %Q(#{verb} "/#{@name}/#{action}", #{class_name}Controller, :#{action}) }.join("\n    ")}
      ROUTES
      add_views
    end

    def parse_actions(actions)
      actions.each do |action|
        next unless action.size > 0
        split_action = action.split(":")
        @actions[split_action.first] = split_action[1]? || "get"
      end
    end

    def add_views
      @actions.each do |action, verb|
        `mkdir -p src/views/#{@name}`
        `touch src/views/#{@name}/#{action}.#{language}`
      end
    end
  end
end
