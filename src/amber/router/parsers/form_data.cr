module Amber::Router::Parsers
  module FormData
    # Parses a URL-encoded request body within `Amber.settings.params`,
    # checking each pair as it streams.
    def self.parse(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      parse_part(request.body, limits)
    end

    def self.parse_part(input : IO, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      ParamBudget.new(limits).parse_form(input)
    end

    def self.parse_part(input : String, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      parse_part(IO::Memory.new(input), limits)
    end

    def self.parse_part(input : Nil, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      HTTP::Params.new
    end
  end
end
