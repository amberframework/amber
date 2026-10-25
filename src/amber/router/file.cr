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
    Log = ::Log.for(self)

    # The preferred upload directory: one per user, which every worker and
    # every restart of the app reuses, so directories never pile up.
    UPLOAD_DIRECTORY = ::File.join(Dir.tempdir, upload_directory_name)

    private UPLOAD_DIRECTORY_LOCK = Mutex.new
    private FALLBACK_ATTEMPTS     = 10

    @@fallback_upload_directory : String?

    private LEFTOVER_LOCK = Mutex.new
    private MAX_LEFTOVERS = 10_000
    @@list_of_leftovers = [] of Tuple(String, ::File::Info)

    # Returns a directory only this user can enter, so no other local user
    # can create or replace files in it: a real directory, owned by this
    # user, with mode 0700.
    #
    # It is `UPLOAD_DIRECTORY`, created when missing. If another user has
    # claimed that path in a shared temporary directory, this process uses a
    # new directory with an unpredictable name instead, and keeps using it.
    def self.upload_directory : String
      UPLOAD_DIRECTORY_LOCK.synchronize do
        preferred = @@fallback_upload_directory || UPLOAD_DIRECTORY
        return preferred if prepare_private_directory?(preferred)

        FALLBACK_ATTEMPTS.times do
          fallback = ::File.tempname(upload_directory_name, nil)
          if prepare_private_directory?(fallback)
            @@fallback_upload_directory = fallback
            return fallback
          end
        end
        raise IO::Error.new("Could not create a private upload directory in #{Dir.tempdir}")
      end
    end

    # Creates *path* with mode 0700 when it does not exist, then reports
    # whether it is a real directory owned by this user and closed to
    # everyone else.
    private def self.prepare_private_directory?(path : String) : Bool
      begin
        Dir.mkdir(path, 0o700)
      rescue ::File::AlreadyExistsError
        # Created by an earlier run, another worker, or someone else.
      end

      directory_info = ::File.info?(path, follow_symlinks: false)
      return false unless directory_info
      return false unless directory_info.directory? && (directory_info.permissions.value & 0o077) == 0
      if user_id = current_user_id
        return false unless directory_info.owner_id == user_id
      end
      true
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
      created_identity = created.info
      copied, identity = begin
        bytes_copied = max_bytes ? ::IO.copy(upload.body, created, max_bytes + 1) : ::IO.copy(upload.body, created)
        if max_bytes && bytes_copied > max_bytes
          raise Amber::Exceptions::ParameterLimitExceeded.new("max_file_bytes", max_bytes)
        end
        created.close
        {bytes_copied, created_identity}
      rescue ex
        self.class.discard(created, created_identity)
        raise ex
      end
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

    # Moves the upload to *destination*, replacing any file there, and
    # returns that path. From then on the file belongs to the caller:
    # Amber's cleanup leaves it alone, and `file` raises.
    #
    # Across file systems the upload is copied to a new file beside
    # *destination* and renamed into place only after the copy succeeds;
    # the tempfile is deleted only after that rename. If the copy fails, the
    # partial copy is removed, *destination* is left as it was, and Amber
    # still owns the tempfile.
    def move_to(destination : String | Path) : String
      tempfile = @tempfile
      if tempfile.moved? || !tempfile.owned_by_amber?
        raise IO::Error.new("The upload was already moved or retained")
      end

      close_handle(tempfile)
      verify_identity!(tempfile)
      target = destination.to_s
      begin
        ::File.rename(tempfile.path, target)
      rescue ex : ::File::Error
        raise ex unless ex.os_error == Errno::EXDEV
        open_tempfile { |source| self.class.copy_into_place(source, target) }
        # The upload is now complete at *target*.
        tempfile.moved = true
        begin
          ::File.delete(tempfile.path)
        rescue ::File::Error
          # The move succeeded. Amber still owns the leftover tempfile and
          # removes it when the request finishes.
          return target
        end
      end
      tempfile.owned_by_amber = false
      tempfile.moved = true
      target
    end

    # :nodoc:
    # Copies *source* into a new file in *target*'s directory, then renames
    # it to *target*, so *target* is either untouched or complete. On any
    # failure the new file is removed and the error is raised. *copy* does
    # the copying; specs pass one that fails.
    def self.copy_into_place(source : IO, target : String, copy : Proc(IO, IO, Nil) = ->(from : IO, to : IO) { ::IO.copy(from, to); nil }) : Nil
      staging = ::File.tempfile(".amber-upload-move", dir: ::File.dirname(target))
      staging_identity = staging.info
      begin
        copy.call(source, staging)
        staging.flush
        staging.fsync
        staging.close
        ::File.rename(staging.path, target)
      rescue ex
        discard(staging, staging_identity)
        raise ex
      end
    end

    # :nodoc:
    # Closes *file* and deletes its path, even when closing fails (for
    # example while flushing onto a full disk). Never raises: callers
    # re-raise their original error. A file that cannot be deleted now is
    # remembered, and `retry_leftover_deletions` deletes it later while its
    # path still names the same file. *identity* is the file's identity
    # taken when it was created; without one it is read from the open
    # handle.
    def self.discard(file : ::File, identity : ::File::Info? = nil) : Nil
      identity ||= begin
        file.info unless file.closed?
      rescue IO::Error
        nil
      end
      begin
        file.close unless file.closed?
      rescue IO::Error
        # The caller's original error is the one to report.
      end

      begin
        ::File.delete?(file.path)
      rescue ex : IO::Error
        Log.warn(exception: ex) { "Could not delete the upload tempfile #{file.path}; retrying later" }
        remember_leftover(file.path, identity) if identity
      end
    end

    # Deletes the tempfiles `discard` could not, when their paths still name
    # the files Amber created; Amber calls it when a request finishes. Files
    # that still cannot be deleted are kept for the next call.
    def self.retry_leftover_deletions : Nil
      list_of_attempts = LEFTOVER_LOCK.synchronize do
        attempts = @@list_of_leftovers
        @@list_of_leftovers = [] of Tuple(String, ::File::Info)
        attempts
      end

      list_of_attempts.each do |path, identity|
        current = ::File.info?(path, follow_symlinks: false)
        ::File.delete(path) if current && current.same_file?(identity)
      rescue IO::Error
        remember_leftover(path, identity)
      end
    end

    # :nodoc:
    # Keeps *path* for `retry_leftover_deletions`. The list is bounded: past
    # `MAX_LEFTOVERS` the path is logged as an error, naming the file for an
    # operator to remove, and is not tracked.
    def self.remember_leftover(path : String, identity : ::File::Info) : Nil
      tracked = LEFTOVER_LOCK.synchronize do
        next false if @@list_of_leftovers.size >= MAX_LEFTOVERS
        @@list_of_leftovers << {path, identity}
        true
      end
      Log.error { "Too many undeletable upload tempfiles; #{path} is not tracked for retry" } unless tracked
    end

    # :nodoc:
    # Hands this upload's tempfile, which could not be deleted, to
    # `retry_leftover_deletions` while Amber still owns it.
    def defer_deletion : Nil
      tempfile = @tempfile
      return if tempfile.moved? || !tempfile.owned_by_amber?
      self.class.remember_leftover(tempfile.path, tempfile.identity)
    end

    # Keeps the tempfile at `path` after the request and returns that path.
    # From then on the caller must delete it; Amber's cleanup only closes
    # the handle that `file` opened.
    def retain! : String
      tempfile = @tempfile
      if tempfile.moved? || !tempfile.owned_by_amber?
        raise IO::Error.new("The upload was already moved or retained")
      end

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
    # it deletes the path if, when checked, it still names the file Amber
    # created (same device and inode, symlinks not followed), then gives up
    # ownership. A failed delete raises and leaves ownership in place, so a
    # later call can retry it. The check and the unlink are two system calls, so code
    # running as this user that swaps the path between them can still lose
    # the file it put there; the private upload directory keeps every other
    # user out. To keep an upload, transfer it with `move_to` or `retain!`,
    # which stop this cleanup entirely.
    #
    # A handle that fails to close does not stop the deletion.
    def delete_tempfile : Nil
      tempfile = @tempfile
      begin
        close_handle(tempfile)
      rescue ex : IO::Error
        Log.warn(exception: ex) { "Could not close the upload handle for #{tempfile.path}" }
      end
      return unless tempfile.owned_by_amber?

      current = ::File.info?(tempfile.path, follow_symlinks: false)
      # Ownership ends only once nothing of Amber's is left at the path, so a
      # failed delete (which raises) can be retried.
      ::File.delete(tempfile.path) if current && current.same_file?(tempfile.identity)
      tempfile.owned_by_amber = false
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
        tempfile.handle = nil
        handle.close
      end
    end
  end
end
