require "http/headers"

module Amber::Router
  # A file uploaded in a multipart request, held in a tempfile that Amber
  # owns until the request finishes.
  #
  # During the action, read the upload through `file`, which opens the
  # tempfile on first use, or through `open_tempfile`. When the request
  # finishes, Amber closes that handle and deletes the tempfile.
  #
  # To keep an upload beyond the request, transfer it during the action:
  #
  # ```
  # # Move it to permanent storage; Amber no longer deletes it.
  # stored_path = params.files["avatar"].move_to("storage/avatars/#{user.id}.png")
  #
  # # Or keep the tempfile where it is and take over deleting it, for
  # # example before handing the path to a background job.
  # ProcessUpload.new(params.files["report"].retain!).enqueue
  # ```
  #
  # Each method transfers ownership once: after `move_to` or `retain!`,
  # Amber's cleanup leaves the path alone.
  struct File
    # A directory only this user can enter, so no other local user can
    # create or replace files in it. Every worker and every restart of the
    # app reuses it, so it is created once and never piles up.
    UPLOAD_DIRECTORY = ::File.join(Dir.tempdir, upload_directory_name)

    # Returns `UPLOAD_DIRECTORY`, creating it with mode 0700 when it does not
    # exist, after checking that it is a real directory, owned by this user
    # and closed to everyone else.
    def self.upload_directory : String
      path = UPLOAD_DIRECTORY
      begin
        Dir.mkdir(path, 0o700)
      rescue ::File::AlreadyExistsError
        # Created by an earlier run, another worker, or this process.
      end

      directory_info = ::File.info(path, follow_symlinks: false)
      private_directory = directory_info.directory? && (directory_info.permissions.value & 0o077) == 0
      if user_id = current_user_id
        private_directory &&= directory_info.owner_id == user_id
      end
      raise IO::Error.new("The upload directory #{path} is not a private directory owned by this user") unless private_directory
      path
    end

    private def self.upload_directory_name : String
      if user_id = current_user_id
        "amber-uploads-#{user_id}"
      else
        "amber-uploads"
      end
    end

    private def self.current_user_id : String?
      {% if flag?(:unix) %}
        LibC.getuid.to_s
      {% end %}
    end

    # The state that every copy of one `File` shares (the struct is copied
    # whenever it is read from `params.files`): the tempfile's path and
    # identity, the handle `file` opened, whether Amber still owns the
    # tempfile and must delete it, and whether it was moved.
    private class Tempfile
      getter path : String
      getter identity : ::File::Info
      property handle : ::File?
      property? owned_by_amber : Bool = true
      property? moved : Bool = false

      def initialize(@path : String, @identity : ::File::Info)
      end
    end

    getter filename : String?
    getter headers : HTTP::Headers
    getter creation_time : Time?
    getter modification_time : Time?
    getter read_time : Time?
    getter size : UInt64?

    @tempfile : Tempfile

    # Copies the upload into a newly created tempfile. With *max_bytes*, a
    # larger upload raises `Amber::Exceptions::ParameterLimitExceeded`; on
    # any failure the tempfile is removed. `size` is the number of bytes
    # copied; the client's declared size is ignored.
    def initialize(upload, max_bytes : Int64? = nil)
      @filename = upload.filename
      # A fixed name plus a short, plain extension: the client's filename is
      # kept only as metadata, so it can never make the tempfile path invalid.
      created = ::File.tempfile("amber-upload", self.class.safe_extension(@filename), dir: self.class.upload_directory)
      copied, identity = begin
        bytes_copied = max_bytes ? ::IO.copy(upload.body, created, max_bytes + 1) : ::IO.copy(upload.body, created)
        if max_bytes && bytes_copied > max_bytes
          raise Amber::Exceptions::ParameterLimitExceeded.new("max_file_bytes", max_bytes)
        end
        {bytes_copied, created.info}
      rescue ex
        created.close
        created.delete
        raise ex
      end
      created.close
      @tempfile = Tempfile.new(created.path, identity)

      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = copied.to_u64
    end

    # The path of the tempfile Amber created.
    def path : String
      @tempfile.path
    end

    # A read handle on the upload, opened on first use and positioned at its
    # start. Amber closes it when the request finishes. Raises `IO::Error`
    # after `move_to`, or when the path no longer names the tempfile.
    def file : ::File
      tempfile = @tempfile
      if handle = tempfile.handle
        return handle
      end
      raise IO::Error.new("The upload was moved; open it at the path move_to returned") if tempfile.moved?

      handle = open_checked(tempfile)
      tempfile.handle = handle
      handle
    end

    # Opens the tempfile for reading after checking that its path still
    # names the file Amber created, yields the handle, and closes it.
    def open_tempfile(& : ::File -> T) : T forall T
      handle = open_checked(@tempfile)
      begin
        yield handle
      ensure
        handle.close
      end
    end

    # Moves the upload to *destination* and returns that path. From then on
    # the file belongs to the caller: Amber's cleanup leaves it alone, and
    # `file` raises. Across file systems the upload is copied, then the
    # tempfile is deleted.
    def move_to(destination : String | Path) : String
      tempfile = @tempfile
      raise IO::Error.new("The upload was already moved or retained") unless tempfile.owned_by_amber?

      close_handle(tempfile)
      verify_identity!(tempfile)
      target = destination.to_s
      begin
        ::File.rename(tempfile.path, target)
      rescue ex : ::File::Error
        raise ex unless ex.os_error == Errno::EXDEV
        open_tempfile do |source|
          ::File.open(target, "w") { |output| ::IO.copy(source, output) }
        end
        ::File.delete(tempfile.path)
      end
      tempfile.owned_by_amber = false
      tempfile.moved = true
      target
    end

    # Keeps the tempfile at `path` after the request and returns that path.
    # From then on the caller must delete it; Amber's cleanup only closes
    # the handle that `file` opened.
    def retain! : String
      tempfile = @tempfile
      raise IO::Error.new("The upload was already moved or retained") unless tempfile.owned_by_amber?

      tempfile.owned_by_amber = false
      tempfile.path
    end

    # Whether Amber still owns the tempfile and will delete it when the
    # request finishes.
    def owned_by_amber? : Bool
      @tempfile.owned_by_amber?
    end

    # Returns the extension of *filename* when it is a dot followed by one to
    # sixteen ASCII letters or digits, and an empty string otherwise.
    def self.safe_extension(filename : String?) : String
      return "" unless filename
      extension = ::File.extname(filename)
      return "" unless 2 <= extension.bytesize <= 17
      plain = extension.byte_slice(1).each_byte.all?(&.unsafe_chr.ascii_alphanumeric?)
      plain ? extension : ""
    end

    # Amber's cleanup, run when the request finishes or its parse fails.
    #
    # Closes the handle `file` opened. When Amber still owns the tempfile,
    # it gives up ownership and deletes the path if, when checked, it still
    # names the file Amber created (same device and inode, symlinks not
    # followed). The check and the unlink are two system calls, so code
    # running as this user that swaps the path between them can still lose
    # the file it put there; the private upload directory keeps every other
    # user out. To keep an upload, transfer it with `move_to` or `retain!`,
    # which stop this cleanup entirely.
    def delete_tempfile : Nil
      tempfile = @tempfile
      close_handle(tempfile)
      return unless tempfile.owned_by_amber?

      tempfile.owned_by_amber = false
      current = ::File.info?(tempfile.path, follow_symlinks: false)
      ::File.delete(tempfile.path) if current && current.same_file?(tempfile.identity)
    end

    private def open_checked(tempfile : Tempfile) : ::File
      handle = ::File.open(tempfile.path, "r")
      unless handle.info.same_file?(tempfile.identity)
        handle.close
        raise IO::Error.new("The upload tempfile was replaced")
      end
      handle
    end

    private def verify_identity!(tempfile : Tempfile) : Nil
      current = ::File.info?(tempfile.path, follow_symlinks: false)
      unless current && current.same_file?(tempfile.identity)
        raise IO::Error.new("The upload tempfile was replaced")
      end
    end

    private def close_handle(tempfile : Tempfile) : Nil
      if handle = tempfile.handle
        handle.close
        tempfile.handle = nil
      end
    end
  end
end
