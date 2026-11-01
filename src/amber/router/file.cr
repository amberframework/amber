require "http/headers"

module Amber::Router
  struct File
    Log = ::Log.for(self)

    getter file : ::File
    getter filename : String?
    getter headers : HTTP::Headers
    getter creation_time : Time?
    getter modification_time : Time?
    getter read_time : Time?
    getter size : UInt64?

    def initialize(upload)
      @filename = upload.filename
      @file = ::File.tempfile(::File.basename(filename.to_s))
      ::File.open(@file.path, "w") do |f|
        ::IO.copy(upload.body, f)
      end
      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = upload.size
    end

    # Delete the tempfile backing this upload.
    #
    # #initialize deliberately streams every upload to disk so that large files
    # never sit in memory. Nothing deleted those tempfiles, so a server leaked
    # one file per uploaded file for its entire lifetime — measured at 5 uploads
    # producing 5 surviving files in $TMPDIR. The request cycle now calls this
    # at teardown; see Amber::Pipe::Pipeline#call.
    #
    # A controller that needs an upload to outlive the request must copy it
    # (::File.rename or ::IO.copy) before returning, which is the same contract
    # other frameworks use for uploaded-file tempfiles.
    #
    # Best effort by design: a tempfile that cannot be deleted is logged, and
    # teardown never raises into the request cycle. Closing an already-closed
    # file is a no-op, and a path the controller already moved is skipped.
    def cleanup : Nil
      @file.close
      ::File.delete?(@file.path)
    rescue error : IO::Error
      Log.warn(exception: error) { "Could not delete the upload tempfile #{@file.path}" }
    end
  end
end
