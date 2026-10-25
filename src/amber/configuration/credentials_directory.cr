require "yaml"

module Amber::Configuration
  # Reads a credentials directory: one file per credential, where the file
  # name is the credential name and the file contents are its value.
  #
  # This is the layout systemd's `LoadCredential=` and
  # `LoadCredentialEncrypted=` produce in `$CREDENTIALS_DIRECTORY`. The
  # reader takes the directory path as an argument and reads files only;
  # the application's configuration decides where the path comes from.
  #
  # Contents are kept byte for byte, including any trailing newline, so
  # write credential files without one (`printf '%s' "$secret"`).
  #
  # Every failure raises a named `Amber::Exceptions::CredentialsError`
  # subclass whose message names the directory and the credential, never
  # its value. The reader does not log.
  #
  # ```
  # struct AppCredentials
  #   include YAML::Serializable
  #
  #   property secret_key_base : String = ""
  #   property database_url : String? = nil
  #
  #   def initialize
  #   end
  # end
  #
  # directory = Amber::Configuration::CredentialsDirectory.new("/run/credentials/app.service")
  # directory.read_credential("secret_key_base") # => "..."
  # directory.read                               # => {"database_url" => "...", "secret_key_base" => "..."}
  # directory.read_into(AppCredentials)          # => AppCredentials(@secret_key_base="...", ...)
  # ```
  class CredentialsDirectory
    # The default cap on a single credential file: 64 KiB.
    DEFAULT_MAXIMUM_FILE_SIZE = 64_i64 * 1024

    # The longest credential name a file system accepts (NAME_MAX).
    MAXIMUM_NAME_SIZE = 255

    getter directory : String
    getter maximum_file_size : Int64

    def initialize(@directory : String, @maximum_file_size : Int64 = DEFAULT_MAXIMUM_FILE_SIZE)
    end

    # Reads every credential in the directory into a hash keyed by file name.
    def read : Hash(String, String)
      base = resolved_directory
      credentials = {} of String => String
      list_of_names(base).each do |name|
        credentials[name] = read_from(base, name)
      end
      credentials
    end

    # Reads one credential by name.
    #
    # Raises `Amber::Exceptions::CredentialPathTraversal` when *name* is not a
    # plain file name, such as `../other_service/key`.
    def read_credential(name : String) : String
      read_from(resolved_directory, name)
    end

    # Reads every credential and builds a typed section from them.
    #
    # Each file name maps to the field with that YAML key. Files with no
    # matching field are ignored; fields with no file keep their default.
    def read_into(type : T.class) : T forall T
      mapping = YAML::Nodes::Mapping.new
      read.each do |name, value|
        mapping[double_quoted_scalar(name)] = double_quoted_scalar(value)
      end

      begin
        T.new(YAML::ParseContext.new, mapping)
      rescue YAML::ParseException
        # The YAML message can quote a value, so it is replaced, not chained.
        raise Amber::Exceptions::CredentialsDoNotFitSection.new(T.name, directory)
      end
    end

    private def resolved_directory : String
      base = File.realpath(directory)
      raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory) unless File.directory?(base)
      base
    rescue File::NotFoundError
      raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory)
    end

    private def read_from(base : String, name : String) : String
      ensure_plain_file_name(name)
      path = resolved_credential_path(base, name)

      credential_file_info = File.info(path)
      raise Amber::Exceptions::CredentialNotARegularFile.new(name, directory) unless credential_file_info.file?
      if credential_file_info.size > maximum_file_size
        raise Amber::Exceptions::CredentialTooLarge.new(name, directory, maximum_file_size)
      end

      read_bounded(path, name)
    end

    private def list_of_names(base : String) : Array(String)
      Dir.children(base).sort!
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory)
    end

    private def ensure_plain_file_name(name : String) : Nil
      if name.empty? || name == "." || name == ".." || name.bytesize > MAXIMUM_NAME_SIZE ||
         name.includes?('/') || name.includes?('\0')
        raise Amber::Exceptions::CredentialPathTraversal.new(name, directory)
      end
    end

    # Returns the real path of the credential, following a symlink only when
    # its target stays inside the credentials directory.
    private def resolved_credential_path(base : String, name : String) : String
      path = File.join(base, name)
      link_info = File.info?(path, follow_symlinks: false)
      raise Amber::Exceptions::CredentialNotFound.new(name, directory) unless link_info
      return path unless link_info.symlink?

      target = begin
        File.realpath(path)
      rescue File::NotFoundError
        # A dangling link has no readable target, wherever it points.
        raise Amber::Exceptions::CredentialNotFound.new(name, directory)
      end
      unless target.starts_with?(base + File::SEPARATOR)
        raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory)
      end
      target
    end

    # Reads at most one byte past the cap, so a file that grows after the
    # size check is still rejected instead of read whole.
    private def read_bounded(path : String, name : String) : String
      contents = IO::Memory.new
      File.open(path, "r") do |file|
        IO.copy(file, contents, maximum_file_size + 1)
      end
      raise Amber::Exceptions::CredentialTooLarge.new(name, directory, maximum_file_size) if contents.size > maximum_file_size
      contents.to_s
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
    end

    # Double-quoted scalars keep every value a string: a credential whose
    # contents are `null` or `true` stays that text in a `String?` field.
    private def double_quoted_scalar(value : String) : YAML::Nodes::Scalar
      scalar = YAML::Nodes::Scalar.new(value)
      scalar.style = YAML::ScalarStyle::DOUBLE_QUOTED
      scalar
    end
  end
end
