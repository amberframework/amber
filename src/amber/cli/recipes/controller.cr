require "file_utils"
require "../templates/field.cr"

module Amber::Recipes
  class Controller < Teeplate::FileTree
    include Amber::CLI::Helpers
    include FileEntries

    getter template

    @name : String
    @actions = Hash(String, String).new
    getter language : String = CLI.config.language
    @action_names : Array(String)

    @template : String | Nil
    @recipe : String | Nil

    def initialize(@name, @recipe, actions)
      parse_actions(actions)
      add_routes :web, <<-ROUTES
        #{@actions.map { |action, verb| %Q(#{verb} "/#{@name}/#{action}", #{class_name}Controller, :#{action}) }.join("\n    ")}
      ROUTES

      @action_names = @actions.map { |action, verb| action}

      @template = RecipeFetcher.new("controller", @recipe).fetch

      add_views
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "class_name", class_name
      ctx.set "display_name", display_name
      ctx.set "name", @name
      ctx.set "actions", @actions
      ctx.set "language", @language
      ctx.set "recipe", @recipe
      ctx.set "action_names", @action_names
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
        FileUtils.mkdir_p("src/views/#{@name}")
        File.touch("src/views/#{@name}/#{action}.#{language}")
      end
    end
  end
end
