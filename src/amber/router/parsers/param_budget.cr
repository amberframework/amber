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
    private OPEN_BRACKET  = '['.ord.to_u8
    private CLOSE_BRACKET = ']'.ord.to_u8

    getter limits : Amber::Configuration::ParamsConfig
    getter param_count : Int32 = 0
    getter padding_used : Int32 = 0

    def initialize(@limits : Amber::Configuration::ParamsConfig = Amber.settings.params)
    end

    # Records one parameter and checks the length of its name and value.
    def admit!(key : String, value : String? = nil) : Nil
      # Compare before incrementing so the count can never overflow.
      exceed!("max_params", limits.max_params) if @param_count >= limits.max_params
      @param_count += 1
      check_key!(key)
      check_value!(value) if value
    end

    def check_key!(key : String) : Nil
      exceed!("max_key_bytes", limits.max_key_bytes) if key.bytesize > limits.max_key_bytes
    end

    def check_value!(value : String) : Nil
      exceed!("max_value_bytes", limits.max_value_bytes) if value.bytesize > limits.max_value_bytes
    end

    # Checks a key's length and nesting depth without splitting it, so a
    # hostile key is rejected before any segment array is built.
    def check_key_shape!(key : String) : Nil
      check_key!(key)
      check_depth!(nested_segment_count(key))
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

      # Subtraction keeps every comparison inside Int32 for any setting.
      padding = index - array.size
      if padding > 0
        gap = limits.max_array_index_gap
        exceed!("max_array_index_gap", gap) if padding > gap

        padding_left = limits.max_array_padding - @padding_used
        exceed!("max_array_padding", limits.max_array_padding) if padding > padding_left
        @padding_used += padding
      end

      while array.size <= index
        array << ::JSON::Any.new(nil)
      end
      index
    end

    # Reads at most *max_bytes* from *io*, raising when more remain.
    def read_bounded(io : IO, max_bytes : Int, limit_name : String) : String
      # A String holds at most Int32::MAX bytes.
      cap = Math.min(max_bytes.to_i64, Int32::MAX.to_i64 - 1)
      buffer = IO::Memory.new
      copied = IO.copy(io, buffer, cap + 1)
      exceed!(limit_name, max_bytes) if copied > cap
      buffer.to_s
    end

    # Reads one field value, bounded by `max_value_bytes`.
    def read_value(io : IO) : String
      read_bounded(io, limits.max_value_bytes, "max_value_bytes")
    end

    # Reads one uploaded file into memory, bounded by `max_file_bytes`.
    def read_file(io : IO) : String
      read_bounded(io, limits.max_file_bytes, "max_file_bytes")
    end

    # Yields each decoded pair of a URL-encoded stream after admitting it.
    #
    # The stream is read one pair at a time and never past the remaining
    # `max_form_body_bytes` allowance. Each raw key and value is size-checked
    # before it is decoded, so the count, key, value and total-size limits
    # reject a hostile body before it is held in memory.
    def each_form_pair(io : IO, & : String, String ->) : Nil
      max_body = limits.max_form_body_bytes.to_i64
      pair_limit = encoded_pair_limit
      bytes_read = 0_i64

      loop do
        allowance = max_body - bytes_read
        read_limit = Math.min(allowance + 1, pair_limit.to_i64 + 1).to_i32
        chunk = io.gets('&', limit: read_limit)
        break unless chunk

        bytes_read += chunk.bytesize
        exceed!("max_form_body_bytes", limits.max_form_body_bytes) if bytes_read > max_body
        # A pair longer than any admissible encoded key and value.
        exceed!("max_value_bytes", limits.max_value_bytes) if chunk.bytesize > pair_limit

        each_raw_pair(chunk) do |raw_key, raw_value|
          key = URI.decode_www_form(raw_key)
          value = URI.decode_www_form(raw_value)
          admit!(key, value)
          yield key, value
        end
      end
    end

    # Decodes a URL-encoded stream into `HTTP::Params`, checking every pair.
    def parse_form(io : IO) : HTTP::Params
      params = HTTP::Params.new
      each_form_pair(io) { |key, value| params.add(key, value) }
      params
    end

    # Splits one `&`-terminated chunk on `;` the way `URI::Params.parse`
    # does, checking the encoded sizes before anything is decoded.
    private def each_raw_pair(chunk : String, & : String, String ->) : Nil
      chunk.chomp('&').split(';') do |segment|
        next if segment.empty?

        if separator = segment.index('=')
          raw_key = segment.byte_slice(0, separator)
          raw_value = segment.byte_slice(separator + 1)
        else
          raw_key = segment
          raw_value = ""
        end

        # Percent-encoding uses at most three bytes per decoded byte.
        exceed!("max_key_bytes", limits.max_key_bytes) if raw_key.bytesize > 3_i64 * limits.max_key_bytes
        exceed!("max_value_bytes", limits.max_value_bytes) if raw_value.bytesize > 3_i64 * limits.max_value_bytes
        yield raw_key, raw_value
      end
    end

    # The longest encoded `key=value&` that can decode within the limits:
    # percent-encoding uses at most three bytes per decoded byte.
    private def encoded_pair_limit : Int32
      longest = 3_i64 * (limits.max_key_bytes.to_i64 + limits.max_value_bytes.to_i64) + 2
      Math.min(longest, Int32::MAX.to_i64 - 1).to_i32
    end

    # Counts the segments the schema parsers split a key into: non-empty runs
    # between `[` and `]`, or dot-separated parts when there are no brackets.
    private def nested_segment_count(key : String) : Int32
      count = 0
      in_segment = false
      key.each_byte do |byte|
        if byte == OPEN_BRACKET || byte == CLOSE_BRACKET
          in_segment = false
        elsif !in_segment
          in_segment = true
          count += 1
        end
      end
      count = key.count('.') + 1 if count == 1 && key.includes?('.')
      count
    end

    # Returns the index written in *digits*, or nil when it is not a plain
    # decimal number from 0 to `max_array_index`. Overflow yields nil.
    private def parse_index(digits : String) : Int32?
      return if digits.empty? || digits.bytesize > 10
      return unless digits.each_byte.all?(&.unsafe_chr.ascii_number?)

      index = digits.to_i?
      return unless index
      return if index > limits.max_array_index
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

    private def exceed!(limit_name : String, limit_value : Int) : NoReturn
      raise Amber::Exceptions::ParameterLimitExceeded.new(limit_name, limit_value)
    end
  end
end
