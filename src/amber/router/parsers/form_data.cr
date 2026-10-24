module Amber::Router::Parsers
  module FormData
    # Parses a URL-encoded request body within `Amber.settings.params`.
    def self.parse(request : HTTP::Request, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      budget = ParamBudget.new(limits)
      body = request.body
      text = body ? budget.read_bounded(body, limits.max_form_body_bytes, "max_form_body_bytes") : ""
      params = HTTP::Params.parse(text)
      params.each { |key, value| budget.admit!(key, value) }
      params
    end

    def self.parse_part(input : IO, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : HTTP::Params
      HTTP::Params.parse(ParamBudget.new(limits).read_bounded(input, limits.max_form_body_bytes, "max_form_body_bytes"))
    end

    def self.parse_part(input : String) : HTTP::Params
      HTTP::Params.parse(input)
    end

    def self.parse_part(input : Nil) : HTTP::Params
      HTTP::Params.parse("")
    end
  end
end
