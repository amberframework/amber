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

    # Copies the upload to a tempfile. With *max_bytes*, a larger upload
    # raises `Amber::Exceptions::ParameterLimitExceeded` and its tempfile is
    # removed.
    def initialize(upload, max_bytes : Int64? = nil)
      @filename = upload.filename
      # A fixed name plus a short, plain extension: the client's filename is
      # kept only as metadata, so it can never make the tempfile path invalid.
      @file = ::File.tempfile("amber-upload", self.class.safe_extension(@filename))
      copied = begin
        ::File.open(@file.path, "w") do |tempfile|
          max_bytes ? ::IO.copy(upload.body, tempfile, max_bytes + 1) : ::IO.copy(upload.body, tempfile)
        end
      rescue ex
        # A limit tripped mid-copy (for example the whole-body cap) must not
        # leave the partial tempfile behind.
        @file.delete
        raise ex
      end
      if max_bytes && copied > max_bytes
        @file.delete
        raise Amber::Exceptions::ParameterLimitExceeded.new("max_file_bytes", max_bytes)
      end
      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = upload.size
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
