module Amber::Router::Parsers
  module Multipart
    # Parses a multipart body within `Amber.settings.params`. Every part,
    # field or file, counts toward `max_params`; field values are bounded by
    # `max_value_bytes`.
    def self.parse(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Tuple(Types::Params, Types::Files)
      multipart_params = Types::Params.new
      files = Types::Files.new
      budget = ParamBudget.new(limits)

      HTTP::FormData.parse(request) do |upload|
        next unless upload
        budget.admit!(upload.name)
        filename = upload.filename
        if filename.is_a?(String) && !filename.empty?
          files[upload.name] = Amber::Router::File.new(upload: upload)
        else
          multipart_params[upload.name] = budget.read_value(upload.body)
        end
      end
      {multipart_params, files}
    end
  end
end
