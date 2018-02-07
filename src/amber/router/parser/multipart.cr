module Parser
  module Multipart
    def self.parse(params : Amber::Router::Params, request : HTTP::Request)
      HTTP::FormData.parse(request) do |upload|
        next unless upload
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          params.files[upload.name] = Amber::Router::File.new(upload: upload)
        else
          params[upload.name] = upload.body.gets_to_end
        end
      end
    end
  end
end
