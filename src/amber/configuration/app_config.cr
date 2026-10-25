require "yaml"

module Amber::Configuration
  class AppConfig
    include YAML::Serializable

    property name : String = "Amber_App"

    @[YAML::Field(key: "server")]
    property server : ServerConfig = ServerConfig.new

    @[YAML::Field(key: "database")]
    property database : DatabaseConfig = DatabaseConfig.new

    @[YAML::Field(key: "session")]
    property session : SessionConfig = SessionConfig.new

    @[YAML::Field(key: "pubsub")]
    property pubsub : PubSubConfig = PubSubConfig.new

    @[YAML::Field(key: "logging")]
    property logging : LoggingConfig = LoggingConfig.new

    @[YAML::Field(key: "jobs")]
    property jobs : JobsConfig = JobsConfig.new

    @[YAML::Field(key: "mailer")]
    property mailer : MailerConfig = MailerConfig.new

    @[YAML::Field(key: "static")]
    property static : StaticConfig = StaticConfig.new

    @[YAML::Field(key: "secrets")]
    property secrets : Hash(String, String) = {} of String => String

    # Custom configuration sections loaded at runtime.
    @[YAML::Field(ignore: true)]
    property custom_configs : Hash(String, YAML::Serializable) = {} of String => YAML::Serializable

    # The YAML node each custom section was loaded from: the section's
    # mapping in the environment file, or the credentials read for a
    # credentials section. The `AMBER_*` override pass rebuilds a section
    # from its source, so fields the type does not serialize keep their
    # loaded values. A section with no source is rebuilt from `to_yaml`.
    @[YAML::Field(ignore: true)]
    property custom_config_sources : Hash(String, YAML::Nodes::Node) = {} of String => YAML::Nodes::Node

    def initialize
    end

    # Retrieve a registered custom configuration section by key and type.
    #
    # ## Example
    #
    # ```
    # stripe = Amber.settings.custom(:stripe, MyApp::StripeConfig)
    # stripe.api_key # => "sk_test_..."
    # ```
    def custom(key : Symbol, type : T.class) : T forall T
      custom_configs[key.to_s].as(T)
    end

    # Run validation on all subsystem configurations.
    # Collects all errors and raises a single ConfigurationError if any are found.
    def validate!(environment : Amber::Environment::Env? = nil) : Nil
      list_of_errors = [] of String

      begin
        server.validate!(environment)
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      begin
        session.validate!
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      begin
        logging.validate!
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      begin
        jobs.validate!
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      begin
        mailer.validate!
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end
  end
end
