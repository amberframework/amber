module Amber::Router::Parsers
  module Multipart
    # Parses a multipart body, charging *budget* (the request's own budget by
    # default). The whole body is bounded by `max_multipart_body_bytes`, each
    # part's headers by `max_part_header_bytes`, and each file by
    # `max_file_bytes` while they stream; every part counts toward
    # `max_params`, and field values are bounded by `max_value_bytes`. If any
    # limit trips, every tempfile already written is removed. A later file
    # part with the same name replaces the earlier one, whose tempfile is
    # removed at once.
    #
    # Amber parses the body before the action runs (the CSRF pipe reads
    # `_csrf` from `params`), which drains it. So that the action can still
    # read `request.body`, a body whose declared `Content-Length` is within
    # `max_multipart_restore_bytes` (and `max_multipart_body_bytes`) is first
    # copied to a tempfile in the private upload directory, parsed from
    # there, and rewound into `request.body`. A larger body, or one without
    # `Content-Length`, is parsed as it streams and stays drained, so a large
    # upload is never copied twice.
    #
    # Returns the fields, the files, and that copy (nil when the body was not
    # copied). The caller deletes the copy when the request finishes, as
    # `Amber::Router::Params#delete_uploaded_files` does.
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : Tuple(Types::Params, Types::Files, ::File?)
      multipart_params = Types::Params.new
      files = Types::Files.new
      list_of_created_files = [] of Amber::Router::File
      limits = budget.limits
      body_copy = copy_body_for_restore(request, limits)

      begin
        each_part(request, limits) do |upload|
          budget.admit!(upload.name)
          filename = upload.filename
          if filename.is_a?(String) && !filename.empty?
            uploaded = Amber::Router::File.new(upload: upload, max_bytes: limits.max_file_bytes)
            list_of_created_files << uploaded
            if replaced = files[upload.name]?
              replaced.delete_tempfile
            end
            files[upload.name] = uploaded
          else
            multipart_params[upload.name] = budget.read_value(upload.body)
          end
        end
      rescue ex
        delete_all(list_of_created_files)
        Amber::Router::File.discard(body_copy) if body_copy
        raise ex
      end

      if body_copy && request.body.same?(body_copy)
        body_copy.rewind
      end
      {multipart_params, files, body_copy}
    end

    # Copies the request body to a tempfile and points the request at it,
    # when its declared `Content-Length` is within both
    # `max_multipart_restore_bytes` and `max_multipart_body_bytes`. Returns
    # nil, copying nothing, otherwise.
    #
    # At most one byte more than the declared length is copied. A body
    # longer than it declared (for example after a pipe replaced
    # `request.body`) is then parsed from the copy followed by the rest of
    # the original body, and stays drained afterwards; the copy is still
    # returned, so it is deleted with the uploads.
    private def self.copy_body_for_restore(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig) : ::File?
      body = request.body
      return unless body

      restore_limit = limits.max_multipart_restore_bytes
      return unless restore_limit > 0

      declared_length = declared_content_length(request)
      return unless declared_length
      return if declared_length == 0
      return if declared_length > restore_limit || declared_length > limits.max_multipart_body_bytes

      body_copy = ::File.tempfile("amber-multipart-body", dir: Amber::Router::File.upload_directory)
      body_copy_identity = body_copy.info
      begin
        copied_length = ::IO.copy(body, body_copy, declared_length + 1)
        body_copy.flush
        body_copy.rewind
      rescue ex
        Amber::Router::File.discard(body_copy, body_copy_identity)
        raise ex
      end

      if copied_length > declared_length
        request.body = ChainedReader.new([body_copy, body] of IO)
        return body_copy
      end

      request.body = body_copy
      body_copy
    end

    # The request's `Content-Length` as a non-negative number, or nil when it
    # is missing or not a number.
    private def self.declared_content_length(request : HTTP::Request) : Int64?
      header_value = request.headers["Content-Length"]?
      return unless header_value

      declared_length = header_value.to_i64?
      return unless declared_length
      return if declared_length < 0
      declared_length
    end

    # Deletes every tempfile in *list_of_files*. One that cannot be deleted
    # is logged and kept for `Amber::Router::File.retry_leftover_deletions`,
    # so the caller's own error is the one raised.
    private def self.delete_all(list_of_files : Array(Amber::Router::File)) : Nil
      list_of_files.each do |uploaded_file|
        uploaded_file.delete_tempfile
      rescue ex : IO::Error
        Amber::Router::File::Log.warn(exception: ex) { "Could not delete the upload tempfile #{uploaded_file.path}; retrying later" }
        uploaded_file.defer_deletion
      end
    end

    # Yields each part of a multipart request. The body is read through a
    # `BoundedIO` capped at `max_multipart_body_bytes`, each part's boundary
    # and headers are capped at `max_part_header_bytes`, and any epilogue
    # after the closing boundary is drained within the body cap. The block
    # must consume each part's body.
    def self.each_part(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig, & : HTTP::FormData::Part ->) : Nil
      body = request.body
      raise Amber::Exceptions::BadRequest.new("The multipart request has no body.") unless body

      content_type = request.headers["Content-Type"]?
      boundary = content_type ? MIME::Multipart.parse_boundary(content_type) : nil
      raise Amber::Exceptions::BadRequest.new("The multipart request has no boundary in its Content-Type.") unless boundary

      bounded_body = BoundedIO.new(body, limits.max_multipart_body_bytes, "max_multipart_body_bytes")
      bounded_body.begin_segment(limits.max_part_header_bytes, "max_part_header_bytes")
      begin
        HTTP::FormData.parse(bounded_body, boundary) do |upload|
          bounded_body.end_segment
          yield upload
          bounded_body.begin_segment(limits.max_part_header_bytes, "max_part_header_bytes")
        end
      rescue ex : HTTP::FormData::Error | MIME::Multipart::Error | ArgumentError | Time::Format::Error | IO::EOFError
        # Malformed framing or part metadata, such as `size=bogus`, is the
        # client's error.
        raise Amber::Exceptions::BadRequest.new("The multipart body is malformed: #{ex.message}")
      end
      bounded_body.end_segment
      bounded_body.skip_to_end
    end
  end
end
