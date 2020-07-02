module Amber::Plugins
  class Fetcher
    Log = ::Log.for(self)

    getter kind : String = "plugin"
    getter name : String
    getter directory : String

    def initialize(@name : String)
      names = name.split(":")
      library_name = names[0]
      stage_name = names[1]
      @directory = "#{Dir.current}/lib/#{library_name}/#{@kind}/#{stage_name}"
    end

    def fetch
      return @directory if Dir.exists?(@directory)

      Log.error { "Cannot generate plugin from #{name}".colorize(:light_red) }
      nil
    end
  end
end
