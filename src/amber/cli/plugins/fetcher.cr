module Amber::Plugins
  class Fetcher
    Log = ::Log.for(self)

    getter kind : String = "plugin"
    getter name : String
    getter directory : String

    def initialize(@name : String)
      @directory = "#{Dir.current}/lib/#{name}/#{kind}"
    end

    def fetch
      return @directory if Dir.exists?(@directory)

      Log.error { "Cannot generate plugin from #{name}".colorize(:light_red) }
      nil
    end
  end
end
