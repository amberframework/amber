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
    def self.parse_multipart_request(request : HTTP::Request) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      HTTP::FormData.parse(request) do |upload|
        next unless upload

        filename = upload.filename
        content = upload.body.gets_to_end

        if filename.is_a?(String) && !filename.empty?
          # This is a file upload
          file_info = FileInfo.new(
            filename: filename,
            content_type: upload.headers["Content-Type"]?,
            size: content.bytesize.to_u64,
            content: content,
            headers: upload.headers
          )
          QueryParser.set_nested_value(result, upload.name, file_info.to_json_any)
        else
          # This is a regular form field
          QueryParser.set_nested_value(result, upload.name, QueryParser.parse_value(content))
        end
      end

      result
    end
  end
end
