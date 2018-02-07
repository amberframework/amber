module Parser
  class FormData
    def self.parse(request : HTTP::Request)
      parse_part(request.body).not_nil!
    end

    def self.parse_part(input : IO?) : HTTP::Params
      HTTP::Params.parse(input.not_nil!.gets_to_end)
    end

    def self.parse_part(input : String?) : HTTP::Params
      HTTP::Params.parse(input.not_nil!)
    end
  end
end
