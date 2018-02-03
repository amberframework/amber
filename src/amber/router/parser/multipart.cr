module Parser
  class Multipart
    def initialize(@params : Amber::Router::Params, @request : HTTP::Request)
    end

    def parse
      HTTP::FormData.parse(@request) do |upload|
        next unless upload
        if valid_filename? upload.filename
          @params.files[upload.name] = Amber::Router::File.new(upload: upload)
        else
          @params[upload.name] = upload.body.gets_to_end
        end
      end
    end

    private def valid_filename?(filename)
      filename.is_a?(String) && !filename.empty?
    end
  end
end