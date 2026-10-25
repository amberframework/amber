module Amber::Exceptions
  # Base class for every error raised while reading a credentials directory.
  #
  # Messages name the directory and the credential file, never its contents,
  # so these errors are safe to log and to show in a crash report.
  class CredentialsError < Exception
  end

  # Raised when the credentials directory does not exist or is not a directory.
  class CredentialsDirectoryNotFound < CredentialsError
    def initialize(directory : String)
      super("Credentials directory not found: #{directory}")
    end
  end

  # Raised when the process may not list the credentials directory.
  class CredentialsDirectoryUnreadable < CredentialsError
    def initialize(directory : String)
      super("Credentials directory #{directory} is not readable by this process")
    end
  end

  # Raised when a credential name could leave the credentials directory:
  # it is empty, `.` or `..`, longer than 255 bytes, or contains `/` or a
  # NUL byte.
  class CredentialPathTraversal < CredentialsError
    def initialize(name : String, directory : String)
      super("Credential name #{name.inspect} is not a plain file name inside #{directory}")
    end
  end

  # Raised when a credential name has no matching file in the directory.
  class CredentialNotFound < CredentialsError
    def initialize(name : String, directory : String)
      super("Credential #{name.inspect} not found in #{directory}")
    end
  end

  # Raised when a credential file is a symlink whose target lies outside
  # the credentials directory.
  class CredentialSymlinkOutsideDirectory < CredentialsError
    def initialize(name : String, directory : String)
      super("Credential #{name.inspect} in #{directory} is a symlink that points outside the directory")
    end
  end

  # Raised when a credential entry is a directory, socket, device, or any
  # other entry that is not a regular file.
  class CredentialNotARegularFile < CredentialsError
    def initialize(name : String, directory : String)
      super("Credential #{name.inspect} in #{directory} is not a regular file")
    end
  end

  # Raised when the process may not read a credential file.
  class CredentialUnreadable < CredentialsError
    def initialize(name : String, directory : String)
      super("Credential #{name.inspect} in #{directory} is not readable by this process")
    end
  end

  # Raised when a credential file is larger than the reader's size cap.
  class CredentialTooLarge < CredentialsError
    def initialize(name : String, directory : String, maximum_file_size : Int64)
      super("Credential #{name.inspect} in #{directory} is larger than the #{maximum_file_size}-byte cap")
    end
  end

  # Raised when the credential files cannot build the registered section
  # type, for example when a non-nilable field has no file and no default.
  # The underlying YAML error is dropped because its message can quote a
  # credential value.
  class CredentialsDoNotFitSection < CredentialsError
    def initialize(type_name : String, directory : String)
      super("Credentials in #{directory} do not fit #{type_name}: every field must be a String " \
            "(or String?) and every field without a default needs a credential file")
    end
  end

  # Raised when a credentials section is registered after `Amber.settings`
  # has already been loaded, because the loaded settings would never see it.
  class CredentialsRegisteredAfterSettingsLoad < CredentialsError
    def initialize(section : String)
      super("Credentials section #{section.inspect} was registered after Amber.settings was loaded; " \
            "require the credentials registration file before anything that reads Amber.settings")
    end
  end
end
