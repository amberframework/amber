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
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : Tuple(Types::Params, Types::Files)
      multipart_params = Types::Params.new
      files = Types::Files.new
      list_of_created_files = [] of Amber::Router::File
      limits = budget.limits

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
        raise ex
      end
      {multipart_params, files}
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
