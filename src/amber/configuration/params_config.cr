require "yaml"

module Amber::Configuration
  # Bounds on the request parameters Amber parses from query strings,
  # URL-encoded bodies, and multipart fields.
  #
  # Every limit has a safe default, so an application that never mentions
  # this section is protected. A request that exceeds a limit is answered
  # with `400 Bad Request` and never allocates in proportion to a number
  # written inside the request.
  #
  # ```yaml
  # # config/environments/production.yml
  # params:
  #   max_array_index: 250
  #   max_params: 2000
  # ```
  #
  # Each value can also be set with an `AMBER_PARAMS_<KEY>` environment
  # variable, for example `AMBER_PARAMS_MAX_ARRAY_INDEX=250`.
  class ParamsConfig
    include YAML::Serializable

    # The largest index accepted in a bracket key such as `items[100]`.
    property max_array_index : Int32 = 100

    # How far past the current end of an array an index may point. An
    # index farther ahead than this is rejected instead of padding the
    # array with empty entries.
    property max_array_index_gap : Int32 = 32

    # The total number of empty entries one request may create while filling
    # gaps between array indices.
    property max_array_padding : Int32 = 1_000

    # The number of parameters (fields and uploads) one request may carry.
    property max_params : Int32 = 1_000

    # The number of segments in one key: `a[b][c]` has three.
    property max_nesting_depth : Int32 = 32

    # The length of one parameter name, in bytes.
    property max_key_bytes : Int32 = 1_024

    # The length of one parameter value, in bytes. Uploaded files are not
    # counted here.
    property max_value_bytes : Int32 = 1_048_576

    # The size of a complete `application/x-www-form-urlencoded` body, in bytes.
    property max_form_body_bytes : Int32 = 8_388_608

    # The size of a complete `multipart/form-data` body, in bytes, counted
    # while it streams.
    property max_multipart_body_bytes : Int64 = 134_217_728_i64

    # The size of one uploaded file, in bytes, counted while it streams.
    # Schema contracts hold uploads in memory, so the accepted range stops
    # at 1 GiB.
    property max_file_bytes : Int64 = 67_108_864_i64

    # The size of one multipart part's boundary line and headers, in bytes.
    property max_part_header_bytes : Int32 = 16_384

    # The size of a JSON, XML, or other document request body that Amber
    # reads for schema validation or `params`, in bytes.
    property max_document_body_bytes : Int32 = 8_388_608

    # The size of one incoming WebSocket message, in bytes, counted across
    # its frames and fragments as they arrive.
    property max_websocket_message_bytes : Int32 = 2_097_152

    # The accepted range of each limit. The ranges keep every limit far from
    # integer overflow and reject settings that would disable a limit.
    INT32_RANGES = {
      "max_array_index"             => 0..1_000_000,
      "max_array_index_gap"         => 0..1_000_000,
      "max_array_padding"           => 0..10_000_000,
      "max_params"                  => 1..1_000_000,
      "max_nesting_depth"           => 1..1_024,
      "max_key_bytes"               => 1..1_048_576,
      "max_value_bytes"             => 1..268_435_456,
      "max_form_body_bytes"         => 1..1_073_741_824,
      "max_part_header_bytes"       => 1..1_048_576,
      "max_websocket_message_bytes" => 125..1_073_741_824,
      "max_document_body_bytes"     => 1..1_073_741_824,
    }

    INT64_RANGES = {
      "max_multipart_body_bytes" => 1_i64..68_719_476_736_i64,
      "max_file_bytes"           => 1_i64..1_073_741_824_i64,
    }

    def initialize
    end

    def validate! : Nil
      list_of_errors = [] of String

      {
        "max_array_index"             => @max_array_index,
        "max_array_index_gap"         => @max_array_index_gap,
        "max_array_padding"           => @max_array_padding,
        "max_params"                  => @max_params,
        "max_nesting_depth"           => @max_nesting_depth,
        "max_key_bytes"               => @max_key_bytes,
        "max_value_bytes"             => @max_value_bytes,
        "max_form_body_bytes"         => @max_form_body_bytes,
        "max_part_header_bytes"       => @max_part_header_bytes,
        "max_websocket_message_bytes" => @max_websocket_message_bytes,
        "max_document_body_bytes"     => @max_document_body_bytes,
      }.each do |name, value|
        range = INT32_RANGES[name]
        list_of_errors << range_error(name, value, range) unless range.includes?(value)
      end

      {
        "max_multipart_body_bytes" => @max_multipart_body_bytes,
        "max_file_bytes"           => @max_file_bytes,
      }.each do |name, value|
        range = INT64_RANGES[name]
        list_of_errors << range_error(name, value, range) unless range.includes?(value)
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end

    private def range_error(name : String, value : Int, range : Range) : String
      "params.#{name} must be between #{range.begin} and #{range.end}, got #{value}"
    end
  end
end
