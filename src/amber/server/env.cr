module Amber
  def self.env
    Env.new(Settings.env.not_nil!.downcase)
  end

  class Env
    def initialize(@env : String | Symbol)
    end

    def in?(environment_list : Array(String | Symbol))
      (environment_list.map &.to_s.downcase).includes? @env
    end

    def is?(environment : String | Symbol)
      @env == environment.to_s.downcase
    end

    def to_s(io)
      io << @env
    end

    private def environments
      (Dir.entries(CONFIG_DIR).map &.downcase.tr(".yml", "") + ENVIRONMENTS).to_set
    end

    macro method_missing(call)
      environment = {{call.name.id.stringify.downcase}}
      if environment.chars.last == '?'
        environment  = environment.downcase.tr("?", "")
        (@env == environment)
      end
    end
  end
end
