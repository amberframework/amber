module Amber::Router::Parsers
  module Multipart    
    def self.parse(request : HTTP::Request) : Tuple(Types::Params, Types::File | Types::Files)
      multipart_params = Types::Params.new
      files = Types::File.new      

      HTTP::FormData.parse(request) do |upload|
        next unless upload
       
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          if files.has_key? upload.name
            if files.is_a? Types::File
              first_file = files[upload.name]
              files = Types::Files.new
              files[upload.name] = [first_file]
            end

            if files.is_a? Types::Files
              files[upload.name] << Amber::Router::File.new(upload: upload)
            end
          else
            files = Types::File.new
            files[upload.name] = Amber::Router::File.new(upload: upload)
          end          
        else
          unless multipart_params.has_key? upload.name
            multipart_params[upload.name] = upload.body.gets_to_end
          end          
        end
      end
      {multipart_params, files}
    end
  end
end
