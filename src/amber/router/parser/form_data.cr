module Parser
  class FormData
    def initialize(@request : HTTP::Request)
    end

    def parse
      parse_part(@request.body).not_nil!
    end

    private def parse_part(input : IO?) : HTTP::Params
      HTTP::Params.parse(input.not_nil!.gets_to_end)
    end

    private def parse_part(input : String?) : HTTP::Params
      HTTP::Params.parse(input.not_nil!)
    end
  end
end