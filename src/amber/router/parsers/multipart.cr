module Amber::Router::Parsers
  module Multipart
    # Parses a multipart body, charging *budget* (the request's own budget by
    # default). The whole body is bounded by `max_multipart_body_bytes`, each
    # part's headers by `max_part_header_bytes`, and each file by
    # `max_file_bytes` while they stream; every part counts toward
    # `max_params`, and field values are bounded by `max_value_bytes`. If any
    # limit trips, the tempfiles already written are removed.
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : Tuple(Types::Params, Types::Files)
      multipart_params = Types::Params.new
      files = Types::Files.new
      limits = budget.limits

      begin
        each_part(request, limits) do |upload|
          budget.admit!(upload.name)
          filename = upload.filename
          if filename.is_a?(String) && !filename.empty?
            files[upload.name] = Amber::Router::File.new(upload: upload, max_bytes: limits.max_file_bytes)
          else
            multipart_params[upload.name] = budget.read_value(upload.body)
          end
        end
      rescue ex
        files.each_value(&.delete_tempfile)
        raise ex
      end
      {multipart_params, files}
    end

    # Yields each part of a multipart request. The body is read through a
    # `BoundedIO` capped at `max_multipart_body_bytes`, each part's boundary
    # and headers are capped at `max_part_header_bytes`, and any epilogue
    # after the closing boundary is drained within the body cap. The block
    # must consume each part's body.
    def self.each_part(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig, & : HTTP::FormData::Part ->) : Nil
      body = request.body
      raise HTTP::FormData::Error.new("Cannot extract form-data from HTTP request: body is empty") unless body

      content_type = request.headers["Content-Type"]?
      boundary = content_type ? MIME::Multipart.parse_boundary(content_type) : nil
      raise HTTP::FormData::Error.new("Cannot extract form-data from HTTP request: could not find boundary in Content-Type") unless boundary

      bounded_body = BoundedIO.new(body, limits.max_multipart_body_bytes, "max_multipart_body_bytes")
      bounded_body.begin_segment(limits.max_part_header_bytes, "max_part_header_bytes")
      HTTP::FormData.parse(bounded_body, boundary) do |upload|
        bounded_body.end_segment
        yield upload
        bounded_body.begin_segment(limits.max_part_header_bytes, "max_part_header_bytes")
      end
      bounded_body.end_segment
      bounded_body.skip_to_end
    end
  end
end
