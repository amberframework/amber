# Query string parser for URL parameters
module Amber::Schema::Parser
  class QueryParser < Base
    def parse(value : JSON::Any) : JSON::Any
      # QueryParser operates on the full params hash, not individual values
      value
    end

    def can_parse?(value : JSON::Any) : Bool
      value.as_h?
    end

    # Parse query string into nested hash structure
    def self.parse_query_string(query_string : String, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Hash(String, JSON::Any)
      params = HTTP::Params.parse(query_string)
      parse_params_to_nested(params, limits)
    end

    # Convert flat params to nested structure.
    #
    # Raises `Amber::Exceptions::ParameterLimitExceeded` when the params
    # exceed *limits*; see `Amber::Configuration::ParamsConfig`.
    def self.parse_params_to_nested(params : HTTP::Params | Hash(String, String), limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any
      budget = Amber::Router::Parsers::ParamBudget.new(limits)

      params.each do |key, value|
        budget.admit!(key, value)
        set_nested_value_internal(result, key, parse_value(value), budget)
      end

      result
    end

    # Handle nested parameter keys like user[profile][name].
    #
    # Pass the same *budget* for every parameter of one request so that its
    # cumulative limits apply.
    def self.set_nested_value(hash : Hash(String, JSON::Any), key : String, value : String | JSON::Any, budget : Amber::Router::Parsers::ParamBudget = Amber::Router::Parsers::ParamBudget.new)
      # Convert string values to JSON::Any
      json_value = value.is_a?(String) ? parse_value(value) : value
      set_nested_value_internal(hash, key, json_value, budget)
    end

    # Internal implementation for nested value setting
    private def self.set_nested_value_internal(hash : Hash(String, JSON::Any), key : String, value : JSON::Any, budget : Amber::Router::Parsers::ParamBudget)
      budget.check_key!(key)
      parts = parse_nested_key(key)
      budget.check_depth!(parts.size)
      parts.each { |part| budget.check_segment!(part) }

      # Handle array notation with indices: tags[0], tags[1]
      if match = key.match(/^(.+)\[(\d+)\]$/)
        base_key = match[1]
        hash[base_key] ||= JSON::Any.new([] of JSON::Any)
        if array = hash[base_key].as_a?
          index = budget.reserve_array_slot!(array, match[2])
          array[index] = value
        end
        return
      end

      # Handle simple array notation: tags[]
      if key.ends_with?("[]")
        base_key = key[0..-3]
        hash[base_key] ||= JSON::Any.new([] of JSON::Any)
        if array = hash[base_key].as_a?
          array << value
        end
        return
      end

      # Handle nested object notation: user[profile][name]
      if parts.size == 1
        # Simple key
        hash[key] = value
      else
        # Nested key
        current = hash
        parts[0..-2].each do |part|
          current[part] ||= JSON::Any.new({} of String => JSON::Any)
          if nested = current[part].as_h?
            current = nested
          else
            # Type conflict, skip this parameter
            return
          end
        end
        current[parts.last] = value
      end
    end

    # Parse nested keys handling both brackets and dots
    private def self.parse_nested_key(key : String) : Array(String)
      # Split on brackets and remove empty parts
      parts = key.split(/[\[\]]/).reject(&.empty?)

      # If no brackets found, try splitting on dots
      if parts.size == 1 && key.includes?('.')
        parts = key.split('.')
      end

      parts
    end

    # Try to parse value as JSON, number, or boolean
    def self.parse_value(value : String) : JSON::Any
      # Try boolean
      return JSON::Any.new(true) if value == "true"
      return JSON::Any.new(false) if value == "false"

      # Try number
      if int_value = value.to_i64?
        return JSON::Any.new(int_value)
      end

      if float_value = value.to_f64?
        return JSON::Any.new(float_value)
      end

      # Try JSON
      if value.starts_with?("{") || value.starts_with?("[")
        begin
          return JSON.parse(value)
        rescue
          # Not valid JSON, treat as string
        end
      end

      # Default to string
      JSON::Any.new(value)
    end

    # Flatten nested hash to query string
    def self.to_query_string(data : Hash(String, JSON::Any), prefix : String? = nil) : String
      params = [] of String

      data.each do |key, value|
        full_key = prefix ? "#{prefix}[#{key}]" : key

        case value.raw
        when Hash
          if nested = value.as_h?
            params << to_query_string(nested, full_key)
          end
        when Array
          if array = value.as_a?
            array.each do |item|
              params << "#{full_key}[]=#{URI.encode_www_form(item.to_s)}"
            end
          end
        else
          params << "#{full_key}=#{URI.encode_www_form(value.to_s)}"
        end
      end

      params.join("&")
    end
  end
end
