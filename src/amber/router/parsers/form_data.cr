module Amber::Router::Parsers
  module FormData
    # Parses a URL-encoded request body, checking each pair as it streams
    # and charging *budget* (the request's own budget by default).
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : HTTP::Params
      body = request.body
      body ? budget.parse_form(body) : HTTP::Params.new
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
