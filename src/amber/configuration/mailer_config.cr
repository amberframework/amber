require "yaml"

module Amber::Configuration
  class SMTPConfig
    include YAML::Serializable

    property host : String = "localhost"
    property port : Int32 = 587
    property username : String? = nil
    property password : String? = nil
    property use_tls : Bool = true
    property helo_domain : String = "localhost"

    def initialize
    end
  end

  class MailerConfig
    include YAML::Serializable

    property adapter : String = "memory"
    property default_from : String = "noreply@example.com"

    @[YAML::Field(key: "smtp")]
    property smtp : SMTPConfig = SMTPConfig.new

    def initialize
    end

    def adapter_symbol : Symbol
      case @adapter
      when "memory" then :memory
      when "smtp"   then :smtp
      else               :memory
      end
    end

    def validate! : Nil
      if @adapter == "smtp"
        if @smtp.host.empty?
          raise Amber::Exceptions::ConfigurationError.new(
            "mailer.smtp.host must be set when mailer adapter is 'smtp'"
          )
        end
        unless @smtp.port.in?(1..65535)
          raise Amber::Exceptions::ConfigurationError.new(
            "mailer.smtp.port must be between 1 and 65535, got #{@smtp.port}"
          )
        end
      end
    end
  end
end
