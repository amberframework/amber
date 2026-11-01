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
  # Each read opens the directory once and then lists, checks and opens
  # every entry relative to that open directory, so replacing the directory
  # or one of its parents with a symlink part way through cannot redirect
  # the read. Each credential file is opened without following a final
  # symlink and without blocking, then checked through the open descriptor,
  # so an entry swapped for a symlink or a FIFO after it was listed is
  # rejected rather than read or waited on. Reads are capped per file and
  # per read. Windows has no credentials directory, and the reader raises
  # `Amber::Exceptions::CredentialsDirectoryUnsupported` there.
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
    {% unless flag?(:win32) %}
      # The POSIX calls that work relative to an open directory, which the
      # standard library does not bind. :nodoc:
      lib LibDirectoryRelative
        fun openat(directory_descriptor : LibC::Int, path : LibC::Char*, flags : LibC::Int, ...) : LibC::Int
        fun readlinkat(directory_descriptor : LibC::Int, path : LibC::Char*, buffer : LibC::Char*, buffer_size : LibC::SizeT) : LibC::SSizeT
        {% if flag?(:darwin) && flag?(:x86_64) %}
          fun fdopendir = "fdopendir$INODE64"(directory_descriptor : LibC::Int) : LibC::DIR*
        {% else %}
          fun fdopendir(directory_descriptor : LibC::Int) : LibC::DIR*
        {% end %}
      end
    {% end %}

    # The open directory one read works through: its descriptor and what it
    # was when it was opened. :nodoc:
    private record OpenDirectory, descriptor : Int32, info : File::Info

    # The default cap on a single credential file: 64 KiB.
    DEFAULT_MAXIMUM_FILE_SIZE = 64_i64 * 1024

    # The default cap on everything one read takes from the directory,
    # counting file names and contents: 1 MiB, systemd's own total limit.
    DEFAULT_MAXIMUM_TOTAL_SIZE = 1_i64 * 1024 * 1024

    # The largest cap either size limit accepts.
    LARGEST_ALLOWED_SIZE = Int32::MAX.to_i64

    # The longest credential name a file system accepts (NAME_MAX).
    MAXIMUM_NAME_SIZE = 255

    # The longest symlink target the reader looks at (PATH_MAX).
    MAXIMUM_LINK_TARGET_SIZE = 4096

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
      with_open_directory do |open_directory|
        credentials = {} of String => String
        total_size = 0_i64
        list_of_names(open_directory).each do |name|
          value = read_from(open_directory, name)
          total_size = add_to_total(total_size, name, value)
          credentials[name] = value
        end
        credentials
      end
    end

    # Reads one credential by name.
    #
    # Raises `Amber::Exceptions::CredentialPathTraversal` when *name* is not a
    # plain file name, such as `../other_service/key`,
    # `Amber::Exceptions::CredentialNotFound` when no file has that name, and
    # `Amber::Exceptions::CredentialsDirectoryTooLarge` when the name and
    # contents exceed `maximum_total_size`.
    def read_credential(name : String) : String
      read_credential?(name) || raise Amber::Exceptions::CredentialNotFound.new(name, directory)
    end

    # Reads one credential by name, or returns nil when no file has that name.
    def read_credential?(name : String) : String?
      with_open_directory do |open_directory|
        value = read_from?(open_directory, name)
        add_to_total(0_i64, name, value) if value
        value
      end
    end

    # Reads the credentials that *type* declares: one file per YAML key of
    # the type, skipping keys with no file. Other files in the directory are
    # neither read nor checked.
    #
    # Raises `Amber::Exceptions::CredentialPathTraversal` when the type
    # declares a key that is not a plain file name.
    def read_for(type : T.class) : Hash(String, String) forall T
      with_open_directory do |open_directory|
        credentials = {} of String => String
        total_size = 0_i64
        SectionField.list_for(type).each do |field|
          name = field.key
          value = read_from?(open_directory, name)
          next unless value
          total_size = add_to_total(total_size, name, value)
          credentials[name] = value
        end
        credentials
      end
    end

    # Reads the credentials that *type* declares and builds the typed section.
    #
    # Each file name maps to the field with that YAML key. Files with no
    # matching field are ignored; fields with no file keep their default.
    def read_into(type : T.class) : T forall T
      self.class.section_from(type, read_for(type), directory)
    end

    # Builds a section of *type* from credential values keyed by YAML key.
    # :nodoc:
    def self.section_from(type : T.class, values : Hash(String, String), directory : String) : T forall T
      T.new(YAML::ParseContext.new, mapping_of(values))
    rescue Exception
      # Any error from building the type, whether from YAML or from the
      # type's own converter or `after_initialize`, can quote a credential
      # value, so it is replaced, not chained.
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

    # Opens the directory once for one read and yields it. Every later
    # step works through this descriptor, never through the path again.
    private def with_open_directory(& : OpenDirectory -> U) : U forall U
      {% if flag?(:win32) %}
        raise Amber::Exceptions::CredentialsDirectoryUnsupported.new(directory)
      {% else %}
        flags = LibC::O_RDONLY | LibC::O_NONBLOCK | LibC::O_CLOEXEC
        descriptor = LibC.open(directory.check_no_null_byte, flags)
        if descriptor < 0
          errno = Errno.value
          if errno.enoent? || errno.enotdir?
            raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory)
          end
          raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory)
        end

        directory_file = IO::FileDescriptor.new(descriptor)
        begin
          directory_info = directory_file.info
          raise Amber::Exceptions::CredentialsDirectoryNotFound.new(directory) unless directory_info.directory?
          yield OpenDirectory.new(descriptor, directory_info)
        ensure
          directory_file.close
        end
      {% end %}
    end

    # Lists the entries of the open directory, counting their names toward
    # the total cap so a directory with a huge number of entries is
    # rejected while it is listed.
    private def list_of_names(open_directory : OpenDirectory) : Array(String)
      {% if flag?(:win32) %}
        [] of String
      {% else %}
        # fdopendir takes over the descriptor it is given, so it gets its own.
        listing_descriptor = LibDirectoryRelative.openat(open_directory.descriptor, ".", LibC::O_RDONLY | LibC::O_CLOEXEC)
        raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory) if listing_descriptor < 0
        listing = LibDirectoryRelative.fdopendir(listing_descriptor)
        if listing.null?
          LibC.close(listing_descriptor)
          raise Amber::Exceptions::CredentialsDirectoryUnreadable.new(directory)
        end

        begin
          list_of_names = [] of String
          name_bytes = 0_i64
          loop do
            entry = LibC.readdir(listing)
            break if entry.null?
            name = String.new(entry.value.d_name.to_unsafe)
            next if name == "." || name == ".."

            name_bytes += name.bytesize
            if name_bytes > maximum_total_size
              raise Amber::Exceptions::CredentialsDirectoryTooLarge.new(directory, maximum_total_size)
            end
            list_of_names << name
          end
          list_of_names.sort!
        ensure
          LibC.closedir(listing)
        end
      {% end %}
    end

    private def read_from(open_directory : OpenDirectory, name : String) : String
      read_from?(open_directory, name) || raise Amber::Exceptions::CredentialNotFound.new(name, directory)
    end

    private def read_from?(open_directory : OpenDirectory, name : String) : String?
      unless plain_file_name?(name)
        raise Amber::Exceptions::CredentialPathTraversal.new(name, directory)
      end
      file = open_entry?(open_directory, name)
      return unless file

      read_open_file(file, name)
    end

    private def plain_file_name?(name : String) : Bool
      !(name.empty? || name == "." || name == ".." || name.bytesize > MAXIMUM_NAME_SIZE ||
        name.includes?('/') || name.includes?('\0'))
    end

    # Opens the entry *name* inside the open directory without following a
    # final symlink and without waiting for a FIFO writer, or returns nil
    # when there is no entry. A symlink is followed one step, and only when
    # its target is a file directly inside the same directory; that target
    # is then opened by name through the open directory, so the read never
    # leaves it.
    private def open_entry?(open_directory : OpenDirectory, name : String) : IO::FileDescriptor?
      descriptor = open_relative(open_directory, name)
      return IO::FileDescriptor.new(descriptor) if descriptor >= 0

      errno = Errno.value
      return if errno.enoent?
      # Permission errors and anything unexpected mean the file cannot be read.
      raise Amber::Exceptions::CredentialUnreadable.new(name, directory) unless symlink_error?(errno)

      target_name = link_target_name?(open_directory, name)
      return unless target_name

      target_descriptor = open_relative(open_directory, target_name)
      return IO::FileDescriptor.new(target_descriptor) if target_descriptor >= 0

      target_errno = Errno.value
      return if target_errno.enoent?
      # A link to a link is refused: only one step is followed.
      raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory) if symlink_error?(target_errno)
      raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
    end

    private def open_relative(open_directory : OpenDirectory, name : String) : Int32
      flags = LibC::O_RDONLY | LibC::O_NOFOLLOW | LibC::O_NONBLOCK | LibC::O_CLOEXEC
      LibDirectoryRelative.openat(open_directory.descriptor, name.check_no_null_byte, flags)
    end

    # `O_NOFOLLOW` on a symlink fails with ELOOP (EMLINK on FreeBSD).
    private def symlink_error?(errno : Errno) : Bool
      errno.eloop? || errno.emlink?
    end

    # Returns the name, inside the open directory, of the file the symlink
    # *name* points to, or nil when the link is dangling. Raises
    # `Amber::Exceptions::CredentialSymlinkOutsideDirectory` when the
    # target is anywhere else.
    private def link_target_name?(open_directory : OpenDirectory, name : String) : String?
      buffer = Bytes.new(MAXIMUM_LINK_TARGET_SIZE)
      target_size = LibDirectoryRelative.readlinkat(open_directory.descriptor, name.check_no_null_byte, buffer, buffer.size)
      if target_size < 0
        # The entry changed between the open and the readlink.
        raise Amber::Exceptions::CredentialUnreadable.new(name, directory)
      end
      if target_size >= buffer.size
        raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory)
      end

      target = String.new(buffer[0, target_size])
      target_name = File.basename(target)
      # A bare file name names an entry of this same directory.
      return target_name unless target.includes?('/')

      target_directory = File.expand_path(File.dirname(target), directory)
      target_directory_info = File.info?(target_directory)
      if target_directory_info && target_directory_info.same_file?(open_directory.info) && plain_file_name?(target_name)
        return target_name
      end

      # A dangling link has no readable target, wherever it points.
      return unless File.exists?(File.expand_path(target, directory))
      raise Amber::Exceptions::CredentialSymlinkOutsideDirectory.new(name, directory)
    end

    # Checks the open descriptor: it must be a regular file no larger than
    # the cap. Reads at most one byte past the cap, so a file that grows
    # after the check is still rejected instead of read whole.
    private def read_open_file(file : IO::FileDescriptor, name : String) : String
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
end
