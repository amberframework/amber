module Amber::Configuration
  # Stores registered custom configuration types as default instances.
  # The key is the YAML section name (e.g., "stripe") and the value
  # is the default instance of the custom config struct.
  #
  # Registration runs while the application's configuration files are
  # required, before any fiber starts, so these class variables are
  # written once at boot and only read afterwards.
  @@custom_config_defaults = {} of String => YAML::Serializable

  # The fields of each registered section's type, so the `AMBER_*`
  # override pass can name its variables, reach fields that are nil or
  # absent, and convert each value to its field's type.
  @@custom_config_fields = {} of String => Array(SectionField)

  # Builds a registered section's type from a YAML mapping node.
  @@custom_config_builders = {} of String => Proc(YAML::Nodes::Node, YAML::Serializable)

  # The values read for each credentials section, keyed by YAML key. The
  # override pass rebuilds a credentials section from these, not from the
  # section's serialized form, which can leave fields out.
  @@credential_values = {} of String => Hash(String, String)

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
  def self.register_custom(key : String, default_instance : T) : Nil forall T
    @@custom_config_defaults[key] = default_instance
    @@custom_config_fields[key] = SectionField.list_for(T)
    @@custom_config_builders[key] = ->(node : YAML::Nodes::Node) do
      T.new(YAML::ParseContext.new, node).as(YAML::Serializable)
    end
  end

  # Registers a typed section whose values are read from a credentials
  # directory: one file per credential, the file name as the key and the
  # contents as the value (the layout of systemd's `$CREDENTIALS_DIRECTORY`).
  # Only the files the section's type declares are read.
  #
  # The section must be registered before the first `Amber.settings` read,
  # so require the file that calls this before anything that reads settings.
  # The application, not Amber, reads `ENV["CREDENTIALS_DIRECTORY"]?` and
  # passes the directory in.
  #
  # Raises `Amber::Exceptions::CredentialsRegisteredAfterSettingsLoad` when
  # `Amber.settings` is already loaded, and any other
  # `Amber::Exceptions::CredentialsError` the directory reader raises.
  #
  # ## Example
  #
  # ```
  # # config/credentials.cr, required by config/application.cr right after "amber"
  # struct AppCredentials
  #   include YAML::Serializable
  #   property secret_key_base : String = ""
  #
  #   def initialize
  #   end
  # end
  #
  # if credentials_directory = ENV["CREDENTIALS_DIRECTORY"]?
  #   Amber::Configuration.register_credentials(:credentials, AppCredentials, credentials_directory)
  # else
  #   Amber::Configuration.register(:credentials, AppCredentials)
  # end
  # ```
  def self.register_credentials(key : Symbol | String, type : T.class, directory : String, *,
                                maximum_file_size : Int64 = CredentialsDirectory::DEFAULT_MAXIMUM_FILE_SIZE,
                                maximum_total_size : Int64 = CredentialsDirectory::DEFAULT_MAXIMUM_TOTAL_SIZE) : Nil forall T
    section = key.to_s
    if Amber.settings_loaded?
      raise Amber::Exceptions::CredentialsRegisteredAfterSettingsLoad.new(section)
    end

    values = CredentialsDirectory.new(directory, maximum_file_size, maximum_total_size).read_for(type)
    store_credentials_section(section, CredentialsDirectory.section_from(type, values, directory), values)
  end

  # Registers an already-read credentials section and keeps its values, so
  # the loader rejects a YAML section with the same key and the override
  # pass can rebuild the section. :nodoc:
  def self.store_credentials_section(key : String, credentials : T, values : Hash(String, String)) : Nil forall T
    register_custom(key, credentials)
    @@credential_values[key] = values
  end

  # Returns true when the section's values come from a credentials directory.
  def self.credential_section?(key : String) : Bool
    @@credential_values.has_key?(key)
  end

  # Returns a fresh YAML mapping of a credentials section's values, or nil
  # when the section does not come from a credentials directory. :nodoc:
  def self.credential_source(key : String) : YAML::Nodes::Mapping?
    if values = @@credential_values[key]?
      CredentialsDirectory.mapping_of(values)
    end
  end

  # Returns all registered custom config keys and their default instances.
  def self.custom_config_defaults : Hash(String, YAML::Serializable)
    @@custom_config_defaults
  end

  # Returns the fields of a registered section's type, or nil when the
  # section is not registered. :nodoc:
  def self.custom_config_fields(key : String) : Array(SectionField)?
    @@custom_config_fields[key]?
  end

  # Builds a registered section from a YAML mapping node, or returns nil
  # when the section is not registered.
  def self.build_custom_from_node(key : String, node : YAML::Nodes::Node) : YAML::Serializable?
    if builder = @@custom_config_builders[key]?
      builder.call(node)
    end
  end

  # Load a custom config from a YAML node, or return the default instance
  # if no YAML node is provided.
  def self.load_custom_from_yaml(key : String, yaml_content : String) : YAML::Serializable?
    if default = @@custom_config_defaults[key]?
      default.class.from_yaml(yaml_content)
    end
  end
end
