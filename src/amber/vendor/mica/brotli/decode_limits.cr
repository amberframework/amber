module Amber::Mica::Brotli
  # Upper bounds on one Brotli decode: the output it may produce, how far
  # the output may outgrow the input, the window it may declare, the
  # metadata it may carry, and the work it may do. Every decode in
  # `Amber::Mica::Brotli` takes them as a required `limits:` argument: use a
  # preset (`REQUEST_BODY`, `HTTP_CLIENT_RESPONSE`, `WEBSOCKET_MESSAGE`,
  # `TRUSTED_ASSET`) or `DecodeLimits.custom`.
  #
  # Each limit is checked before the bytes it guards exist. The window a
  # stream declares is refused before any buffer is allocated, and the
  # decoder raises `DecodeLimitError` the moment the next output byte
  # would pass `max_output_bytes`, so a decompression bomb costs at most
  # `max_output_bytes` of output plus the declared window.
  #
  # The work allowance follows `Core::WorkBudget`: one unit per input byte
  # read and per output byte produced, and
  #
  #     allowance = min(base_work + work_per_unit * units, work_ceiling)
  #
  # Decoding charges one operation per unit, plus the prefix-code table
  # entries each metablock header builds and the context-map entries it
  # fills, so only streams that spend their input on headers approach it.
  #
  # ```
  # limits = Amber::Mica::Brotli::DecodeLimits.custom(max_output_bytes: 1_048_576_i64)
  # limits.max_window_bytes # => 4_194_304 (from REQUEST_BODY)
  # ```
  struct DecodeLimits
    # The ratio check starts once a decode has produced this many bytes,
    # so small, highly compressible bodies never trip it.
    RATIO_GRACE_BYTES = 1_048_576_i64

    # The largest window RFC 7932 allows (WBITS 24).
    MAX_WINDOW_BYTES = 16_777_216

    # Total decoded bytes.
    getter max_output_bytes : Int64
    # Output bytes per input byte consumed, checked once the output passes
    # `RATIO_GRACE_BYTES`.
    getter max_ratio : Int64
    # The largest window (`1 << WBITS`) a stream may declare. A stream
    # declaring more raises `DecodeLimitError` before any allocation.
    getter max_window_bytes : Int32
    # Metadata metablock bytes (skipped, never returned) per stream.
    getter max_metadata_bytes : Int32
    # Work operations allowed per unit (input byte or output byte).
    getter work_per_unit : Int64
    # Work operations allowed regardless of size.
    getter base_work : Int64
    # An absolute cap on work operations, or nil for none.
    getter work_ceiling : Int64?

    def initialize(@max_output_bytes : Int64, @max_ratio : Int64, @max_window_bytes : Int32,
                   @max_metadata_bytes : Int32, @work_per_unit : Int64, @base_work : Int64,
                   @work_ceiling : Int64? = nil)
      check_not_negative("max_output_bytes", @max_output_bytes)
      raise ArgumentError.new("max_ratio must be positive") if @max_ratio < 1
      unless 1_024 <= @max_window_bytes <= MAX_WINDOW_BYTES
        raise ArgumentError.new("max_window_bytes must be between 1024 and #{MAX_WINDOW_BYTES}")
      end
      check_not_negative("max_metadata_bytes", @max_metadata_bytes.to_i64)
      check_not_negative("work_per_unit", @work_per_unit)
      check_not_negative("base_work", @base_work)
      if ceiling = @work_ceiling
        check_not_negative("work_ceiling", ceiling)
      end
    end

    # Returns limits that start from `REQUEST_BODY` and change only the
    # values given.
    def self.custom(*, max_output_bytes : Int64 = REQUEST_BODY.max_output_bytes,
                    max_ratio : Int64 = REQUEST_BODY.max_ratio,
                    max_window_bytes : Int32 = REQUEST_BODY.max_window_bytes,
                    max_metadata_bytes : Int32 = REQUEST_BODY.max_metadata_bytes,
                    work_per_unit : Int64 = REQUEST_BODY.work_per_unit,
                    base_work : Int64 = REQUEST_BODY.base_work,
                    work_ceiling : Int64? = REQUEST_BODY.work_ceiling) : self
      new(max_output_bytes, max_ratio, max_window_bytes, max_metadata_bytes, work_per_unit, base_work, work_ceiling)
    end

    # Returns the work budget these limits allow, with an optional
    # wall-clock *timeout*.
    def work_budget(timeout : Time::Span?) : Core::WorkBudget
      Core::WorkBudget.new(operations_per_unit: @work_per_unit, base_operations: @base_work,
        max_operations: @work_ceiling, timeout: timeout)
    end

    private def check_not_negative(name : String, value : Int64) : Nil
      raise ArgumentError.new("#{name} must not be negative") if value < 0
    end

    # For request bodies an Amber app accepts: 8 MiB of output (Amber's
    # `max_document_body_bytes`), 200:1, a 4 MiB window (WBITS 22, what
    # encoders use by default), 64 KiB of metadata.
    REQUEST_BODY = new(
      max_output_bytes: 8_388_608_i64,
      max_ratio: 200_i64,
      max_window_bytes: 4_194_304,
      max_metadata_bytes: 65_536,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For response bodies an HTTP client reads from a server it does not
    # control: 64 MiB of output, the full 16 MiB window.
    HTTP_CLIENT_RESPONSE = new(
      max_output_bytes: 67_108_864_i64,
      max_ratio: 200_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_metadata_bytes: 65_536,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For one WebSocket message: 1 MiB of output, a 1 MiB window, no
    # metadata.
    WEBSOCKET_MESSAGE = new(
      max_output_bytes: 1_048_576_i64,
      max_ratio: 200_i64,
      max_window_bytes: 1_048_576,
      max_metadata_bytes: 0,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For files the program ships or built itself (precompressed assets):
    # 1 GiB of output, the full window, no ratio bound below Brotli's own.
    TRUSTED_ASSET = new(
      max_output_bytes: 1_073_741_824_i64,
      max_ratio: 1_000_000_000_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_metadata_bytes: 16_777_216,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )
  end
end
