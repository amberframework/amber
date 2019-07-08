module Amber::Router::Parsers
  module Multipart
    def self.parse(request : HTTP::Request) : Tuple(Types::Params, Types::UploadFile)
      multipart_params = Types::Params.new
      files = Types::File.new

      HTTP::FormData.parse(request) do |upload|
        next unless upload

        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          files = get_upload_files(files, upload)
        else
          next if multipart_params.has_key? upload.name

          multipart_params[upload.name] = upload.body.gets_to_end
        end
      end
      {multipart_params, files}
    end

    def self.get_upload_files(files : Types::UploadFile, upload : HTTP::FormData::Part) : Types::UploadFile
      if files.has_key? upload.name
        if files.is_a? Types::File
          first_upload = files[upload.name]
          files = Types::Files.new
          files[upload.name] = [first_upload]
        end

        files = files.as Types::Files
        files[upload.name] << Amber::Router::File.new(upload: upload)
      else
        files = files.as Types::File
        files[upload.name] = Amber::Router::File.new(upload: upload)
      end

      files
    end
  end
end
