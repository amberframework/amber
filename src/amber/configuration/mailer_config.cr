require "yaml"

module Amber::Configuration
  class SMTPConfig
    include YAML::Serializable

    property host : String = "localhost"
    property port : Int32 = 587
    property username : String? = nil
    property password : String? = nil
    # STARTTLS after the greeting (port 587). TLS 1.3 only.
    property use_tls : Bool = true
    # TLS from the first byte (port 465, RFC 8314). TLS 1.3 only; when set,
    # `use_tls` is not used.
    property use_implicit_tls : Bool = false
    # A PEM file of the certificates the mail server's chain is verified
    # against, in place of the Mozilla roots, e.g. a private CA.
    property ca_certificates_file : String? = nil
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
