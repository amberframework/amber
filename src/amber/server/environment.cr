module Amber
  def self.env
    @@env ||= Environment.new(ENV["AMBER_ENV"]? || "development")
  end

  class Environment
    alias EnvType = String | Symbol

    def initialize(@env : String)
    end

    def in?(env_list : Array(EnvType))
      env_list.any? { |env2| self == env2 }
    end

    def in?(*env_list : Object)
      in?(env_list.to_a)
    end

    def to_s(io)
      io << @env
    end

    def ==(env2 : EnvType)
      @env == env2.to_s.downcase
    end

    macro method_missing(call)
      env2 = {{call.name.id.stringify}}
      self == env2[0..-2] if env2.ends_with? '?'
    end
  end
end
