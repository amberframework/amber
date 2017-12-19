module Amber::Environment
  class Env
    AMBER_ENV = "AMBER_ENV"

    def initialize(@env : String = ENV[AMBER_ENV]? || "development")
      ENV[AMBER_ENV] = @env
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
      env_name = {{call.name.id.stringify}}
      (env_name.ends_with?('?') && self == env_name[0..-2])
    end
  end
end
