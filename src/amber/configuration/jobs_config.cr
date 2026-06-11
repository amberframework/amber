require "yaml"

module Amber::Configuration
  class JobsConfig
    include YAML::Serializable

    property adapter : String = "memory"
    property queues : Array(String) = ["default"]
    property workers : Int32 = 1
    property work_stealing : Bool = false
    property polling_interval_seconds : Float64 = 1.0
    property scheduler_interval_seconds : Float64 = 5.0
    property auto_start : Bool = false

    def initialize
    end

    def adapter_symbol : Symbol
      case @adapter
      when "memory" then :memory
      else               :memory
      end
    end

    def polling_interval : Time::Span
      @polling_interval_seconds.seconds
    end

    def scheduler_interval : Time::Span
      @scheduler_interval_seconds.seconds
    end

    def validate! : Nil
      unless @workers >= 1
        raise Amber::Exceptions::ConfigurationError.new(
          "jobs.workers must be at least 1, got #{@workers}"
        )
      end

      unless @polling_interval_seconds > 0
        raise Amber::Exceptions::ConfigurationError.new(
          "jobs.polling_interval_seconds must be positive, got #{@polling_interval_seconds}"
        )
      end

      unless @scheduler_interval_seconds > 0
        raise Amber::Exceptions::ConfigurationError.new(
          "jobs.scheduler_interval_seconds must be positive, got #{@scheduler_interval_seconds}"
        )
      end
    end
  end
end
