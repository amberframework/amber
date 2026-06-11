module Amber::Configuration
  # Stores registered custom configuration types as default instances.
  # The key is the YAML section name (e.g., "stripe") and the value
  # is the default instance of the custom config struct.
  @@custom_config_defaults = {} of String => YAML::Serializable

  # Register a custom configuration type with the Amber settings system.
  #
  # After registration, the config can be loaded from YAML files under
  # the given key and accessed via `Amber.settings.custom(:key, Type)`.
  #
  # ## Example
  #
  # ```
  # struct MyAppConfig
  #   include YAML::Serializable
  #   property api_key : String = ""
  #
  #   def initialize
  #   end
  # end
  #
  # Amber::Configuration.register(:my_app, MyAppConfig)
  # ```
  macro register(key, config_type)
    Amber::Configuration.register_custom({{ key.id.stringify }}, {{ config_type }}.new)
  end

  # Runtime registration method called by the `register` macro.
  def self.register_custom(key : String, default_instance : YAML::Serializable) : Nil
    @@custom_config_defaults[key] = default_instance
  end

  # Returns all registered custom config keys and their default instances.
  def self.custom_config_defaults : Hash(String, YAML::Serializable)
    @@custom_config_defaults
  end

  # Load a custom config from a YAML node, or return the default instance
  # if no YAML node is provided.
  def self.load_custom_from_yaml(key : String, yaml_content : String) : YAML::Serializable?
    if default = @@custom_config_defaults[key]?
      default.class.from_yaml(yaml_content)
    end
  end
end
