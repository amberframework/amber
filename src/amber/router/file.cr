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
      @file = ::File.tempfile(::File.basename(filename.to_s))
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
  end
end
