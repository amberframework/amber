module Amber::Router::Parsers
  module Multipart
    # Parses a multipart body within `Amber.settings.params`. The whole body
    # is bounded by `max_multipart_body_bytes` and each file by
    # `max_file_bytes` while they stream; every part, field or file, counts
    # toward `max_params`, and field values are bounded by `max_value_bytes`.
    def self.parse(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Tuple(Types::Params, Types::Files)
      multipart_params = Types::Params.new
      files = Types::Files.new
      budget = ParamBudget.new(limits)

      each_part(request, limits) do |upload|
        budget.admit!(upload.name)
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          files[upload.name] = Amber::Router::File.new(upload: upload, max_bytes: limits.max_file_bytes)
        else
          multipart_params[upload.name] = budget.read_value(upload.body)
        end
      end
      {multipart_params, files}
    end

    # Yields each part of a multipart request whose body is read through a
    # `BoundedIO` capped at `max_multipart_body_bytes`.
    def self.each_part(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig, & : HTTP::FormData::Part ->) : Nil
      body = request.body
      raise HTTP::FormData::Error.new("Cannot extract form-data from HTTP request: body is empty") unless body

      content_type = request.headers["Content-Type"]?
      boundary = content_type ? MIME::Multipart.parse_boundary(content_type) : nil
      raise HTTP::FormData::Error.new("Cannot extract form-data from HTTP request: could not find boundary in Content-Type") unless boundary

      bounded_body = BoundedIO.new(body, limits.max_multipart_body_bytes, "max_multipart_body_bytes")
      HTTP::FormData.parse(bounded_body, boundary) do |upload|
        yield upload
      end
    end
  end
end
