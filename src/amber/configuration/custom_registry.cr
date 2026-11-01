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

  # Writes each registered default as YAML, every field it reads included,
  # so the override pass, which starts from it when the environment file
  # has no such section, keeps the default's values. Each writer is typed
  # to its own section, so writing never dispatches over every
  # `YAML::Serializable` type in the program.
  @@custom_config_default_writers = {} of String => Proc(String)

  # Reads YAML as each registered section's type and raises when it does
  # not fit. Typed per section, like the writers, so it never reads
  # through the `YAML::Serializable` union.
  @@custom_config_checks = {} of String => Proc(String, Nil)

  # The values read for each credentials section, keyed by YAML key. The
  # loader stores a credentials section from these, and the override pass
  # starts from them.
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
    @@custom_config_default_writers[key] = -> { SectionField.yaml_of(default_instance) }
    @@custom_config_checks[key] = ->(section_yaml : String) do
      T.from_yaml(section_yaml)
      nil
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
  # the loader stores the section from them and rejects a YAML section with
  # the same key. :nodoc:
  def self.store_credentials_section(key : String, credentials : T, values : Hash(String, String)) : Nil forall T
    register_custom(key, credentials)
    @@credential_values[key] = values
  end

  # Returns true when the section's values come from a credentials directory.
  def self.credential_section?(key : String) : Bool
    @@credential_values.has_key?(key)
  end

  # Returns a credentials section as YAML, each value a double-quoted
  # string, or nil when the section does not come from a credentials
  # directory. The loader stores it as the section's YAML. :nodoc:
  def self.credential_source(key : String) : String?
    if values = @@credential_values[key]?
      mapping = CredentialsDirectory.mapping_of(values)
      YAML.build { |builder| mapping.to_yaml(builder) }
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

  # Returns a registered section's default instance written as YAML, every
  # field it reads included, or nil when the section is not registered.
  # :nodoc:
  def self.custom_default_yaml(key : String) : String?
    if writer = @@custom_config_default_writers[key]?
      writer.call
    end
  end

  # Raises when *section_yaml* does not read as the type registered for
  # *key*: a `YAML::ParseException`, or whatever the type's converter or
  # `after_initialize` raises. Does nothing for an unregistered key. :nodoc:
  def self.check_custom_yaml(key : String, section_yaml : String) : Nil
    if check = @@custom_config_checks[key]?
      check.call(section_yaml)
    end
  end
end
