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

    @[YAML::Field(key: "params")]
    property params : ParamsConfig = ParamsConfig.new

    @[YAML::Field(key: "secrets")]
    property secrets : Hash(String, String) = {} of String => String

    # Custom configuration sections loaded at runtime, as the raw YAML of each
    # section keyed by section name. Storing YAML rather than
    # `YAML::Serializable` instances keeps Amber from deserializing through the
    # union of every `YAML::Serializable` type in the program; that union
    # includes application models (Grant models among them), and their YAML
    # constructors may not compile.
    @[YAML::Field(ignore: true)]
    property custom_configs : Hash(String, String) = {} of String => String

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
    #
    # The section is deserialized as *type* on each call, so keep the result
    # rather than calling this per request. When the YAML has no such section,
    # the default instance given to `Amber::Configuration.register` is returned.
    def custom(key : Symbol, type : T.class) : T forall T
      key_name = key.to_s
      if section_yaml = custom_configs[key_name]?
        return T.from_yaml(section_yaml)
      end

      registered_default = Amber::Configuration.custom_config_defaults[key_name]?
      return registered_default if registered_default.is_a?(T)

      raise Amber::Exceptions::ConfigurationError.new("Custom config #{key_name} is not registered as #{T}")
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

      begin
        params.validate!
      rescue ex : Amber::Exceptions::ConfigurationError
        list_of_errors.concat(ex.list_of_errors)
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end
  end
end
