module Amber::Router::Parsers
  module Multipart
    # Parse a multipart form and, when the payload is small enough, hand the
    # request body back afterwards.
    #
    # Amber parses the body for its OWN reasons long before user code runs — the
    # CSRF plug looks for `_csrf` in `context.params` on every state-changing
    # request — so a controller behind the :web pipeline read `request.body` and
    # got "" on every file-upload POST. Measured on a running server: 628 bytes
    # declared, 0 readable.
    #
    # The urlencoded parser solves this by buffering the body in an IO::Memory.
    # That is NOT safe here. A multipart body carries file uploads and can be
    # arbitrarily large, and Router::File streams each part to disk precisely so
    # that uploads never sit in memory; buffering the payload in RAM would undo
    # that and turn a large upload into a memory-exhaustion vector. So the body
    # is spooled to a TEMPFILE instead, and that spool is deleted at request
    # teardown along with the uploads themselves.
    #
    # The spool is bounded by `Amber.settings.multipart_body_restore_limit`.
    # Above the cap — or when Content-Length is absent, as with a chunked body —
    # nothing is spooled and the body is left drained, which is exactly the
    # pre-existing behavior. An oversized upload therefore degrades to what
    # Amber did before rather than filling the disk.
    #
    # Returns the parsed params, the files, and the spool (nil when the body was
    # not spooled) so that Params can delete it at teardown.
    def self.parse(request : HTTP::Request) : Tuple(Types::Params, Types::Files, ::File?)
      multipart_params = Types::Params.new
      files = Types::Files.new

      spool = spool_body(request)

      HTTP::FormData.parse(request) do |upload|
        next unless upload
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          files[upload.name] = Amber::Router::File.new(upload: upload)
        else
          multipart_params[upload.name] = upload.body.gets_to_end
        end
      end

      # The parser consumed the spool, so rewind before the controller reads it.
      if spool
        spool.rewind
        request.body = spool
      end

      {multipart_params, files, spool}
    end

    # Copy the body to a tempfile and point the request at it, so the same bytes
    # can be replayed after parsing. Returns nil when the body must not be
    # spooled, in which case the caller keeps today's streaming behavior.
    private def self.spool_body(request : HTTP::Request) : ::File?
      body = request.body
      return nil if body.nil?

      limit = Amber.settings.multipart_body_restore_limit
      return nil if limit <= 0

      # Decide from Content-Length BEFORE reading a single byte: an over-cap or
      # unknown-length body must never be copied even once.
      declared = request.headers["Content-Length"]?.try(&.to_i64?)
      return nil if declared.nil? || declared > limit

      spool = ::File.tempfile("amber-multipart-body")
      begin
        ::IO.copy(body, spool)
        spool.flush
        spool.rewind
      rescue error
        # Never leak the spool we just created if the copy failed partway.
        spool.close
        ::File.delete?(spool.path)
        raise error
      end

      request.body = spool
      spool
    end
  end
end
