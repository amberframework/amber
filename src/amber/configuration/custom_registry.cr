module Amber::Configuration
  # Stores registered custom configuration types as default instances.
  # The key is the YAML section name (e.g., "stripe") and the value
  # is the default instance of the custom config struct.
  #
  # Registration runs while the application's configuration files are
  # required, before any fiber starts, so these class variables are
  # written once at boot and only read afterwards.
  @@custom_config_defaults = {} of String => YAML::Serializable

  # The YAML keys of each registered section's type, so the `AMBER_*`
  # override pass can reach fields whose value is nil and is therefore
  # missing from the serialized section.
  @@custom_config_keys = {} of String => Array(String)

  # Builds a registered section's type from a YAML mapping node.
  @@custom_config_builders = {} of String => Proc(YAML::Nodes::Node, YAML::Serializable)

  # Sections whose values come from a credentials directory.
  @@credential_sections = Set(String).new

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

  # Register a typed section whose values are read from a credentials
  # directory: one file per credential, the file name as the key and the
  # contents as the value (the layout of systemd's `$CREDENTIALS_DIRECTORY`).
  #
  # The section must be registered before the first `Amber.settings` read,
  # so require the file that calls this before anything that reads settings.
  # The application, not Amber, reads `ENV["CREDENTIALS_DIRECTORY"]?` and
  # passes the directory in.
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
  macro register_credentials(key, config_type, directory, maximum_file_size = Amber::Configuration::CredentialsDirectory::DEFAULT_MAXIMUM_FILE_SIZE)
    Amber::Configuration.register_credentials_section(
      {{ key.id.stringify }}, {{ config_type }}, {{ directory }}, {{ maximum_file_size }}
    )
  end

  # Runtime registration method called by the `register` macro.
  def self.register_custom(key : String, default_instance : T) : Nil forall T
    @@custom_config_defaults[key] = default_instance
    @@custom_config_keys[key] = yaml_keys_of(T)
    @@custom_config_builders[key] = ->(node : YAML::Nodes::Node) do
      T.new(YAML::ParseContext.new, node).as(YAML::Serializable)
    end
  end

  # Runtime registration method called by the `register_credentials` macro.
  #
  # Raises `Amber::Exceptions::CredentialsRegisteredAfterSettingsLoad` when
  # `Amber.settings` is already loaded, and any other
  # `Amber::Exceptions::CredentialsError` the directory reader raises.
  def self.register_credentials_section(key : String, type : T.class, directory : String,
                                        maximum_file_size : Int64 = CredentialsDirectory::DEFAULT_MAXIMUM_FILE_SIZE) : Nil forall T
    if Amber.settings_loaded?
      raise Amber::Exceptions::CredentialsRegisteredAfterSettingsLoad.new(key)
    end

    credentials = CredentialsDirectory.new(directory, maximum_file_size).read_into(type)
    store_credentials_section(key, credentials)
  end

  # Registers an already-read credentials section and marks it as one, so
  # the loader rejects a YAML section with the same key. :nodoc:
  def self.store_credentials_section(key : String, credentials : T) : Nil forall T
    register_custom(key, credentials)
    @@credential_sections << key
  end

  # Returns true when the section's values come from a credentials directory.
  def self.credential_section?(key : String) : Bool
    @@credential_sections.includes?(key)
  end

  # Returns all registered custom config keys and their default instances.
  def self.custom_config_defaults : Hash(String, YAML::Serializable)
    @@custom_config_defaults
  end

  # Returns the YAML keys of a registered section's type, or nil when the
  # section is not registered.
  def self.custom_config_keys(key : String) : Array(String)?
    @@custom_config_keys[key]?
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

  # Lists the YAML keys `YAML::Serializable` reads for *type*, honoring
  # `@[YAML::Field(key: ...)]` renames and skipping ignored fields.
  private def self.yaml_keys_of(type : T.class) : Array(String) forall T
    list_of_keys = [] of String
    {% for ivar in T.instance_vars %}
      {% field = ivar.annotation(::YAML::Field) %}
      {% unless field && (field[:ignore] || field[:ignore_deserialize]) %}
        list_of_keys << {{ field && field[:key] ? field[:key].id.stringify : ivar.name.stringify }}
      {% end %}
    {% end %}
    list_of_keys
  end
end
