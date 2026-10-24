require "http/headers"

module Amber::Router
  struct File
    getter file : ::File
    getter filename : String?
    getter headers : HTTP::Headers
    getter creation_time : Time?
    getter modification_time : Time?
    getter read_time : Time?
    getter size : UInt64?

    # The identity (device and inode) of the tempfile Amber created.
    getter tempfile_info : ::File::Info

    # Copies the upload into a newly created tempfile through the handle
    # that created it, then closes the handle. With *max_bytes*, a larger
    # upload raises `Amber::Exceptions::ParameterLimitExceeded`; on any
    # failure the handle is closed and the tempfile removed. `size` is the
    # number of bytes copied; the client's declared size is ignored.
    def initialize(upload, max_bytes : Int64? = nil)
      @filename = upload.filename
      # A fixed name plus a short, plain extension: the client's filename is
      # kept only as metadata, so it can never make the tempfile path invalid.
      @file = ::File.tempfile("amber-upload", self.class.safe_extension(@filename))
      copied, info = begin
        bytes_copied = max_bytes ? ::IO.copy(upload.body, @file, max_bytes + 1) : ::IO.copy(upload.body, @file)
        if max_bytes && bytes_copied > max_bytes
          raise Amber::Exceptions::ParameterLimitExceeded.new("max_file_bytes", max_bytes)
        end
        {bytes_copied, @file.info}
      rescue ex
        @file.close
        @file.delete
        raise ex
      end
      @file.close
      @tempfile_info = info

      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = copied.to_u64
    end

    # Opens the tempfile for reading after checking that its path still
    # names the file Amber created, and yields the handle.
    def open_tempfile(& : ::File -> T) : T forall T
      ::File.open(@file.path, "r") do |handle|
        unless handle.info.same_file?(@tempfile_info)
          raise IO::Error.new("The upload tempfile was replaced")
        end
        yield handle
      end
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

    # Removes the tempfile; a file the action already moved is left alone.
    def delete_tempfile : Nil
      path = @file.path
      ::File.delete(path) if ::File.exists?(path)
    end
  end
end
