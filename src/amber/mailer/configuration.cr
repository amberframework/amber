module Amber::Mailer
  # Configuration for the Amber mailer system.
  #
  # Manages adapter selection and SMTP connection settings. Uses a singleton
  # pattern to provide a single global configuration instance.
  #
  # ## Configuration
  #
  # ```
  # Amber::Mailer::Configuration.configure do |config|
  #   config.adapter = :smtp
  #   config.smtp_host = "smtp.example.com"
  #   config.smtp_port = 587
  #   config.smtp_username = "user@example.com"
  #   config.smtp_password = "secret"
  #   config.use_tls = true
  #   config.default_from = "noreply@example.com"
  #   config.helo_domain = "example.com"
  # end
  # ```
  #
  # ## Adapters
  #
  # Two built-in adapters are available:
  # - `:memory` - Stores emails in memory (default, ideal for testing)
  # - `:smtp` - Delivers emails via SMTP protocol
  class Configuration
    property adapter : Symbol = :memory
    property smtp_host : String = "localhost"
    property smtp_port : Int32 = 587
    property smtp_username : String? = nil
    property smtp_password : String? = nil
    property use_tls : Bool = true
    property default_from : String = "noreply@example.com"
    property helo_domain : String = "localhost"

    @@instance : Configuration?

    # Returns the singleton configuration instance.
    #
    # Creates a new instance with default values if one does not exist.
    def self.instance : Configuration
      @@instance ||= Configuration.new
    end

    # Yields the singleton configuration instance for modification.
    #
    # ```
    # Amber::Mailer::Configuration.configure do |config|
    #   config.adapter = :smtp
    # end
    # ```
    def self.configure(&) : Nil
      yield instance
    end

    # Resets the configuration to default values.
    #
    # Useful in tests to ensure a clean configuration state.
    def self.reset : Nil
      @@instance = Configuration.new
    end

    # Builds a delivery adapter instance based on the current configuration.
    #
    # Returns a `MemoryAdapter` for `:memory` or an `SMTPAdapter` configured
    # with the current SMTP settings for `:smtp`.
    #
    # Raises `ArgumentError` if the adapter symbol is not recognized.
    def build_adapter : DeliveryAdapter
      case @adapter
      when :memory
        MemoryAdapter.new
      when :smtp
        SMTPAdapter.new(
          host: @smtp_host,
          port: @smtp_port,
          username: @smtp_username,
          password: @smtp_password,
          use_tls: @use_tls,
          helo_domain: @helo_domain,
        )
      else
        raise ArgumentError.new(
          "Unknown mailer adapter: #{@adapter}. Available adapters: :memory, :smtp"
        )
      end
    end
  end
end
