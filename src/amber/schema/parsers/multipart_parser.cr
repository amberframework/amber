# Enhanced multipart form data parser with file upload support
require "http"

module Amber::Schema::Parser
  # File upload validator for schema field validation
  class FileUploadValidator
    def self.validate_file(field_name : String, file_data : JSON::Any, options : Hash(String, JSON::Any)) : Array(Error)
      errors = [] of Error

      return errors unless file_hash = file_data.as_h?

      # Check if this is actually a file upload
      filename = file_hash["filename"]?.try(&.as_s?)
      unless filename
        errors << CustomValidationError.new(field_name, "Expected file upload", "not_a_file")
        return errors
      end

      content = file_hash["content"]?.try(&.as_s?) || ""
      content_type = file_hash["content_type"]?.try(&.as_s?)
      size = file_hash["size"]?.try(&.as_i64?) || content.bytesize.to_i64

      # Validate file size
      if max_size = options["max_size"]?.try(&.as_i64?)
        if size > max_size
          errors << CustomValidationError.new(
            field_name,
            "File size #{size} bytes exceeds maximum of #{max_size} bytes",
            "file_too_large"
          )
        end
      end

      if min_size = options["min_size"]?.try(&.as_i64?)
        if size < min_size
          errors << CustomValidationError.new(
            field_name,
            "File size #{size} bytes is below minimum of #{min_size} bytes",
            "file_too_small"
          )
        end
      end

      # Validate content type
      if allowed_types = options["allowed_types"]?.try(&.as_a?)
        if content_type
          type_strings = allowed_types.map(&.as_s)
          unless type_strings.includes?(content_type)
            errors << CustomValidationError.new(
              field_name,
              "Content type '#{content_type}' not allowed. Allowed types: #{type_strings.join(", ")}",
              "invalid_content_type"
            )
          end
        else
          errors << CustomValidationError.new(
            field_name,
            "Content type missing for file upload",
            "missing_content_type"
          )
        end
      end

      # Validate file extensions
      if allowed_extensions = options["allowed_extensions"]?.try(&.as_a?)
        extension = File.extname(filename).downcase
        ext_strings = allowed_extensions.map(&.as_s).map(&.downcase)
        unless ext_strings.includes?(extension)
          errors << CustomValidationError.new(
            field_name,
            "File extension '#{extension}' not allowed. Allowed extensions: #{ext_strings.join(", ")}",
            "invalid_file_extension"
          )
        end
      end

      # Validate filename pattern
      if pattern = options["filename_pattern"]?.try(&.as_s?)
        regex = Regex.new(pattern)
        unless filename.matches?(regex)
          errors << CustomValidationError.new(
            field_name,
            "Filename '#{filename}' does not match required pattern: #{pattern}",
            "invalid_filename_pattern"
          )
        end
      end

      errors
    end
  end

  # Enhanced multipart parser that creates file data structures
  class MultipartParser
    # File info structure for multipart uploads
    struct FileInfo
      getter filename : String?
      getter content_type : String?
      getter size : UInt64?
      getter content : String
      getter headers : HTTP::Headers

      def initialize(@filename, @content_type, @size, @content, @headers)
      end

      def to_json_any : JSON::Any
        data = {} of String => JSON::Any
        data["filename"] = JSON::Any.new(@filename) if @filename
        data["content_type"] = JSON::Any.new(@content_type) if @content_type
        data["size"] = JSON::Any.new(@size.not_nil!.to_i64) if @size
        data["content"] = JSON::Any.new(@content)

        # Add headers as a nested object
        headers_hash = {} of String => JSON::Any
        @headers.each do |name, values|
          if values.size == 1
            headers_hash[name] = JSON::Any.new(values[0])
          else
            headers_hash[name] = JSON::Any.new(values.map { |v| JSON::Any.new(v) })
          end
        end
        data["headers"] = JSON::Any.new(headers_hash)

        JSON::Any.new(data)
      end
    end

    # Parse multipart form data, handling both files and regular fields
    def self.parse_multipart_request(request : HTTP::Request, budget : Amber::Router::Parsers::ParamBudget = request.param_budget) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any
      request.guard_body_read { collect_multipart_parts(request, budget, result) }
      result
    end

    private def self.collect_multipart_parts(request : HTTP::Request, budget : Amber::Router::Parsers::ParamBudget, result : Hash(String, JSON::Any)) : Nil
      Amber::Router::Parsers::Multipart.each_part(request, budget.limits) do |upload|
        budget.admit!(upload.name)
        filename = upload.filename

        # The key is checked, and its array slot reserved, before the part's
        # body is read.
        read = QueryParser.set_nested_value(result, upload.name, budget) do
          if filename.is_a?(String) && !filename.empty?
            # Held in memory, so bounded by `max_file_bytes`; the whole body
            # is bounded by `max_multipart_body_bytes`.
            content = budget.read_file(upload.body)
            FileInfo.new(
              filename: filename,
              content_type: upload.headers["Content-Type"]?,
              size: content.bytesize.to_u64,
              content: content,
              headers: upload.headers
            ).to_json_any
          else
            QueryParser.parse_value(budget.read_value(upload.body))
          end
        end
        # A skipped part (its key conflicts with an earlier value) is drained
        # within its own cap, so parsing can continue.
        unless read
          if filename.is_a?(String) && !filename.empty?
            budget.skip_bounded(upload.body, budget.limits.max_file_bytes, "max_file_bytes")
          else
            budget.skip_bounded(upload.body, budget.limits.max_value_bytes, "max_value_bytes")
          end
        end
      end
    end

    # Builds schema data from the router's cached multipart parse. This keeps
    # file uploads available after routing and CSRF have inspected the request.
    # Every field and file is admitted against a fresh budget built from
    # *limits*.
    def self.parse_router_params(params : Amber::Router::Types::Params, files : Amber::Router::Types::Files, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Hash(String, JSON::Any)
      budget = Amber::Router::Parsers::ParamBudget.new(limits)
      params.each { |key, value| budget.admit!(key, value) }
      files.each_key { |name| budget.admit!(name) }
      parse_router_params(params, files, budget)
    end

    # Builds schema data from fields and files that *budget* already admitted
    # (the request's own budget charged them while routing parsed the body).
    # One budget covers fields and files, so padding stays cumulative.
    def self.parse_router_params(params : Amber::Router::Types::Params, files : Amber::Router::Types::Files, budget : Amber::Router::Parsers::ParamBudget) : Hash(String, JSON::Any)
      result = QueryParser.parse_admitted_params(params, budget)

      files.each do |name, upload|
        # The key is checked before the tempfile is read.
        QueryParser.set_nested_value(result, name, budget) do
          content = upload.open_tempfile { |file| budget.read_file(file) }
          FileInfo.new(
            filename: upload.filename,
            content_type: upload.headers["Content-Type"]?,
            # The bytes received, never the client's declared size.
            size: content.bytesize.to_u64,
            content: content,
            headers: upload.headers
          ).to_json_any
        end
      end

      result
    end
  end
end
