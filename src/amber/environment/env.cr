module Amber::Environment
  class Env
    AMBER_ENV = "AMBER_ENV"

    def initialize(env : String = ENV[AMBER_ENV]? || "development")
      ENV[AMBER_ENV] = @env = env.downcase
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
      {% if call.name.id.stringify.ends_with?("?") %}
        (@env == {{ call.name.id.stringify.downcase[0..-2] }})
      {% else %}
        false
      {% end %}
    end
  end
end
