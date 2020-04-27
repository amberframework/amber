module Amber::Plugins

  class PluginInstaller < Teeplate::FileTree
    include Amber::CLI::Helpers
    include Amber::Recipes::FileEntries

    property template : String | Nil

    property name : String
    getter language : String = CLI.config.language
    property timestamp : String

    def initialize(@name)
      @template = PluginFetcher.new(name).fetch
      @timestamp = Time.utc.to_s("%Y%m%d%H%M%S%L")
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "name", name
      ctx.set "language", language
    end

  end
end