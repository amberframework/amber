require "yaml"
require "./section_field"

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
  # Each credential file is opened without following a final symlink and
  # without blocking, then checked through the open descriptor, so an entry
  # swapped for a symlink or a FIFO after it was listed is rejected rather
  # than read or waited on. Reads are capped per file and per directory.
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

    # The default cap on everything one read takes from the directory,
    # counting file names and contents: 1 MiB, systemd's own total limit.
    DEFAULT_MAXIMUM_TOTAL_SIZE = 1_i64 * 1024 * 1024

    # The largest cap either size limit accepts.
    LARGEST_ALLOWED_SIZE = Int32::MAX.to_i64

    # The longest credential name a file system accepts (NAME_MAX).
    MAXIMUM_NAME_SIZE = 255

    getter directory : String
    getter maximum_file_size : Int64
    getter maximum_total_size : Int64

    # Raises `ArgumentError` when a cap is negative or above
    # `LARGEST_ALLOWED_SIZE`.
    def initialize(@directory : String, @maximum_file_size : Int64 = DEFAULT_MAXIMUM_FILE_SIZE,
                   @maximum_total_size : Int64 = DEFAULT_MAXIMUM_TOTAL_SIZE)
      ensure_allowed_size("maximum_file_size", @maximum_file_size)
      ensure_allowed_size("maximum_total_size", @maximum_total_size)
    end

    # Reads every credential in the directory into a hash keyed by file name.
    #
    # Raises `Amber::Exceptions::CredentialsDirectoryTooLarge` when the file
    # names and contents together exceed `maximum_total_size`.
    def read : Hash(String, String)
      base = resolved_directory
      credentials = {} of String => String
      total_size = 0_i64
      list_of_names(base).each do |name|
        value = read_from(base, name)
        total_size = add_to_total(total_size, name, value)
        credentials[name] = value
      end
      credentials
    end

    # Reads one credential by name.
    #
    # Raises `Amber::Exceptions::CredentialPathTraversal` when *name* is not a
    # plain file name, such as `../other_service/key`, and
    # `Amber::Exceptions::CredentialNotFound` when no file has that name.
    def read_credential(name : String) : String
      read_from(resolved_directory, name)
    end

    # Reads one credential by name, or returns nil when no file has that name.
    def read_credential?(name : String) : String?
      read_from?(resolved_directory, name)
    end

    # Reads the credentials that *type* declares: one file per YAML key of
    # the type, skipping keys with no file. Other files in the directory are
    # neither read nor checked.
    def read_for(type : T.class) : Hash(String, String) forall T
      base = resolved_directory
      credentials = {} of String => String
      total_size = 0_i64
      SectionField.list_for(type).each do |field|
        name = field.key
        next unless plain_file_name?(name)
        value = read_from?(base, name)
        next unless value
        total_size = add_to_total(total_size, name, value)
        credentials[name] = value
      end
      credentials
    end

    # Reads the credentials that *type* declares and builds the typed section.
    #
    # Each file name maps to the field with that YAML key. Files with no
    # matching field are ignored; fields with no file keep their default.
    def read_into(type : T.class) : T forall T
      self.class.section_from(type, read_for(type), directory)
    end

    # Builds a section of *type* from credential values keyed by YAML key.
    # The YAML error is replaced, not chained, because it can quote a value.
    # :nodoc:
    def self.section_from(type : T.class, values : Hash(String, String), directory : String) : T forall T
      T.new(YAML::ParseContext.new, mapping_of(values))
    rescue YAML::ParseException
      raise Amber::Exceptions::CredentialsDoNotFitSection.new(T.name, directory)
    end

    # Builds a YAML mapping of double-quoted scalars from credential values,
    # so a credential whose contents are `null` or `true` stays that text in
    # a `String?` field. :nodoc:
    def self.mapping_of(values : Hash(String, String)) : YAML::Nodes::Mapping
      mapping = YAML::Nodes::Mapping.new
      values.each do |name, value|
        mapping[double_quoted_scalar(name)] = double_quoted_scalar(value)
      end
      mapping
    end

    private def self.double_quoted_scalar(value : String) : YAML::Nodes::Scalar
      scalar = YAML::Nodes::Scalar.new(value)
      scalar.style = YAML::ScalarStyle::DOUBLE_QUOTED
      scalar
    end

    private def ensure_allowed_size(argument : String, size : Int64) : Nil
      unless 0 <= size <= LARGEST_ALLOWED_SIZE
        raise ArgumentError.new("#{argument} must be between 0 and #{LARGEST_ALLOWED_SIZE} bytes")
      end
    end

    private def add_to_total(total_size : Int64, name : String, value : String) : Int64
      new_total = total_size + name.bytesize + value.bytesize
      if new_total > maximum_total_size
        raise Amber::Exceptions::CredentialsDirectoryTooLarge.new(directory, maximum_total_size)
      end
      new_total
    end

    private def resolved_directory : String
      base = File.realpath(directory)
      raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory) unless File.directory?(base)
      base
    rescue File::NotFoundError
      raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory)
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory)
    end

    # Lists the entries, counting their names toward the total cap so a
    # directory with a huge number of entries is rejected while it is listed.
    private def list_of_names(base : String) : Array(String)
      list_of_names = [] of String
      name_bytes = 0_i64
      Dir.each_child(base) do |name|
        name_bytes += name.bytesize
        if name_bytes > maximum_total_size
          raise Amber::Exceptions::CredentialsDirectoryTooLarge.new(directory, maximum_total_size)
        end
        list_of_names << name
      end
      list_of_names.sort!
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory)
    end

    private def read_from(base : String, name : String) : String
      read_from?(base, name) || raise Amber::Exceptions::CredentialNotFound.new(name, directory)
    end

    private def read_from?(base : String, name : String) : String?
      unless plain_file_name?(name)
        raise Amber::Exceptions::CredentialPathTraversal.new(name, directory)
      end
      if path = resolved_credential_path?(base, name)
        read_open_file(path, name)
      end
    end

    private def plain_file_name?(name : String) : Bool
      !(name.empty? || name == "." || name == ".." || name.bytesize > MAXIMUM_NAME_SIZE ||
        name.includes?('/') || name.includes?('\0'))
    end

    # Returns the path to open for the credential, or nil when there is no
    # entry. A symlink is followed only when its target is a file directly
    # inside the credentials directory, so the path that is opened has no
    # component below the directory that could itself be swapped for a link.
    private def resolved_credential_path?(base : String, name : String) : String?
      path = File.join(base, name)
      link_info = File.info?(path, follow_symlinks: false)
      return unless link_info
      return path unless link_info.symlink?

      target = begin
        File.realpath(path)
      rescue File::NotFoundError
        # A dangling link has no readable target, wherever it points.
        return
      end
      unless File.dirname(target) == base
        raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory)
      end
      target
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
    end

    # Opens *path* and checks the open descriptor: it must be a regular file
    # no larger than the cap. Reads at most one byte past the cap, so a file
    # that grows after the check is still rejected instead of read whole.
    private def read_open_file(path : String, name : String) : String
      file = open_without_following(path, name)
      begin
        credential_file_info = file.info
        raise Amber::Exceptions::CredentialNotARegularFile.new(name, directory) unless credential_file_info.file?
        if credential_file_info.size > maximum_file_size
          raise Amber::Exceptions::CredentialTooLarge.new(name, directory, maximum_file_size)
        end

        contents = IO::Memory.new
        IO.copy(file, contents, maximum_file_size + 1)
        if contents.size > maximum_file_size
          raise Amber::Exceptions::CredentialTooLarge.new(name, directory, maximum_file_size)
        end
        contents.to_s
      ensure
        file.close
      end
    end

    # Opens the final path component without following a symlink
    # (`O_NOFOLLOW`) and without waiting for a FIFO writer (`O_NONBLOCK`).
    private def open_without_following(path : String, name : String) : IO::FileDescriptor
      {% if flag?(:win32) %}
        File.new(path, "r")
      {% else %}
        flags = LibC::O_RDONLY | LibC::O_NOFOLLOW | LibC::O_NONBLOCK | LibC::O_CLOEXEC
        descriptor = LibC.open(path.check_no_null_byte, flags)
        if descriptor < 0
          raise_open_error(Errno.value, name)
        end
        IO::FileDescriptor.new(descriptor)
      {% end %}
    rescue File::NotFoundError
      raise Amber::Exceptions::CredentialNotFound.new(name, directory)
    rescue File::AccessDeniedError
      raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
    end

    private def raise_open_error(errno : Errno, name : String) : NoReturn
      if errno.enoent?
        raise Amber::Exceptions::CredentialNotFound.new(name, directory)
      elsif errno.eloop?
        # The entry became a symlink after it was checked.
        raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory)
      else
        raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
      end
    end
  end
end
