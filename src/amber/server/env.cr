module Amber
  def self.env
    @@env ||= Env.new(ENV["AMBER_ENV"]? || "development") # Would be best to only define this once.
  end

  class Env
    alias EnvType = String | Symbol 

    def initialize(@env : String) end

    def is?(environment : EnvType)
      @env == environment.to_s.downcase
    end

    def in?(environment_list : Array(EnvType))
      environment_list.each do |other_env|
        return true if is?(other_env)
      end
    end

    def in?(*environment_list : Object)
      in?(environment_list.to_a)
    end

    def to_s(io)
      io << @env
    end

    def ==(other : EnvType)
      is?(other)
    end

    macro method_missing(call)
      if (environment = {{call.name.id.stringify}}).ends_with? '?'
        is?(environment[0..-2])
      end
    end
  end
end
