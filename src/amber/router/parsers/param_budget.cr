require "json"

module Amber::Router::Parsers
  # Enforces `Amber::Configuration::ParamsConfig` while one request's
  # parameters are parsed.
  #
  # Create one budget per request and pass it to every parsing step for that
  # request: the parameter count and the array padding are cumulative. Each
  # check raises `Amber::Exceptions::ParameterLimitExceeded`, which Amber
  # answers with `400 Bad Request`.
  #
  # ```
  # budget = Amber::Router::Parsers::ParamBudget.new
  # budget.admit!("items[3]", "x")
  # index = budget.reserve_array_slot!(list_of_items, "3")
  # list_of_items[index] = JSON::Any.new("x")
  # ```
  class ParamBudget
    getter limits : Amber::Configuration::ParamsConfig
    getter param_count : Int32 = 0
    getter padding_used : Int32 = 0

    def initialize(@limits : Amber::Configuration::ParamsConfig = Amber.settings.params)
    end

    # Records one parameter and checks the length of its name and value.
    def admit!(key : String, value : String? = nil) : Nil
      @param_count += 1
      exceed!("max_params", limits.max_params) if @param_count > limits.max_params
      check_key!(key)
      check_value!(value) if value
    end

    def check_key!(key : String) : Nil
      exceed!("max_key_bytes", limits.max_key_bytes) if key.bytesize > limits.max_key_bytes
    end

    def check_value!(value : String) : Nil
      exceed!("max_value_bytes", limits.max_value_bytes) if value.bytesize > limits.max_value_bytes
    end

    # Checks the number of segments in one key, such as 3 for `a[b][c]`.
    def check_depth!(segment_count : Int32) : Nil
      exceed!("max_nesting_depth", limits.max_nesting_depth) if segment_count > limits.max_nesting_depth
    end

    # Rejects a key segment written as a negative integer, such as `items[-1]`.
    def check_segment!(segment : String) : Nil
      invalid_index! if negative_integer?(segment)
    end

    # Converts the digits of a bracket index and makes room for it in *array*.
    #
    # Returns the index, now within `array.size`. The index must be at most
    # `max_array_index` and at most `max_array_index_gap` past the end of the
    # array, and the empty entries added to reach it count toward
    # `max_array_padding`.
    def reserve_array_slot!(array : Array(::JSON::Any), digits : String) : Int32
      index = parse_index(digits)
      invalid_index! unless index

      gap = limits.max_array_index_gap
      exceed!("max_array_index_gap", gap) if index > array.size + gap

      padding = index - array.size
      if padding > 0
        @padding_used += padding
        exceed!("max_array_padding", limits.max_array_padding) if @padding_used > limits.max_array_padding
      end

      while array.size <= index
        array << ::JSON::Any.new(nil)
      end
      index
    end

    # Reads at most *max_bytes* from *io*, raising when more remain.
    def read_bounded(io : IO, max_bytes : Int32, limit_name : String) : String
      buffer = IO::Memory.new
      copied = IO.copy(io, buffer, max_bytes.to_i64 + 1)
      exceed!(limit_name, max_bytes) if copied > max_bytes
      buffer.to_s
    end

    # Reads one field value, bounded by `max_value_bytes`.
    def read_value(io : IO) : String
      read_bounded(io, limits.max_value_bytes, "max_value_bytes")
    end

    # Returns the index written in *digits*, or nil when it is not a plain
    # decimal number from 0 to `max_array_index`. Overflow yields nil.
    private def parse_index(digits : String) : Int32?
      return nil if digits.empty? || digits.bytesize > 10
      return nil unless digits.each_byte.all?(&.unsafe_chr.ascii_number?)

      index = digits.to_i?
      return nil unless index
      return nil if index > limits.max_array_index
      index
    end

    private def negative_integer?(segment : String) : Bool
      return false unless segment.bytesize > 1 && segment.starts_with?('-')
      segment.byte_slice(1).each_byte.all?(&.unsafe_chr.ascii_number?)
    end

    private def invalid_index! : NoReturn
      raise Amber::Exceptions::ParameterLimitExceeded.new(
        "Request parameter array indices must be whole numbers from 0 to #{limits.max_array_index}.",
        "max_array_index",
        limits.max_array_index
      )
    end

    private def exceed!(limit_name : String, limit_value : Int32) : NoReturn
      raise Amber::Exceptions::ParameterLimitExceeded.new(limit_name, limit_value)
    end
  end
end
