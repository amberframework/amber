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

    def initialize
    end

    def validate! : Nil
      list_of_errors = [] of String

      {
        "max_array_index"     => @max_array_index,
        "max_array_index_gap" => @max_array_index_gap,
        "max_array_padding"   => @max_array_padding,
        "max_params"          => @max_params,
        "max_nesting_depth"   => @max_nesting_depth,
        "max_key_bytes"       => @max_key_bytes,
        "max_value_bytes"     => @max_value_bytes,
        "max_form_body_bytes" => @max_form_body_bytes,
      }.each do |name, value|
        list_of_errors << "params.#{name} must be at least 1, got #{value}" if value < 1
      end

      unless list_of_errors.empty?
        raise Amber::Exceptions::ConfigurationError.new(list_of_errors)
      end
    end
  end
end
