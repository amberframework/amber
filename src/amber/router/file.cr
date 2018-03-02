require "http/headers"
require "tempfile"

module Amber::Router
  struct File
    getter file : Tempfile
    getter filename : String?
    getter headers : HTTP::Headers
    getter creation_time : Time?
    getter modification_time : Time?
    getter read_time : Time?
    getter size : UInt64?

    def initialize(upload)
      @filename = upload.filename
      @file = Tempfile.new(filename)
      ::File.open(@file.path, "w") do |f|
        ::IO.copy(upload.body, f)
      end
      @headers = upload.headers
      @creation_time = upload.creation_time
      @modification_time = upload.modification_time
      @read_time = upload.read_time
      @size = upload.size
    end
  end
end
