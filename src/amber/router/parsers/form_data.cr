module Amber::Router::Parsers
  module FormData
    def self.parse(request : HTTP::Request)
      parse_part(request.body).not_nil!
    end

    def self.parse_part(input : IO) : HTTP::Params
      HTTP::Params.parse(input.gets_to_end)
    end

    def self.parse_part(input : String) : HTTP::Params
      HTTP::Params.parse(input.to_s)
    end

    def self.parse_part(input : Nil) : HTTP::Params
      HTTP::Params.parse("")
    end
  end
end
