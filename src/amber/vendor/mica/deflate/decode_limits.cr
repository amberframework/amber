module Amber::Mica::Deflate
  # Upper bounds on one decode: the output it may produce, how far the
  # output may outgrow the input, the history it may use, the gzip members
  # and metadata it may carry, and the work it may do. Every decode in
  # `Amber::Mica::Deflate`, `Amber::Mica::Zlib` and `Amber::Mica::Gzip` takes them as a required
  # `limits:` argument (there is no default): use a preset (`REQUEST_BODY`,
  # `HTTP_CLIENT_RESPONSE`, `WEBSOCKET_MESSAGE`, `TRUSTED_ASSET`) or
  # `DecodeLimits.custom`.
  #
  # Every limit is checked before the bytes it guards exist: the decoder
  # raises `DecodeLimitError` naming the limit the moment the next output
  # byte would pass `max_output_bytes`, so a decompression bomb costs at
  # most `max_output_bytes` of output plus fixed buffers, whatever it
  # declares.
  #
  # The work allowance follows `Core::WorkBudget`: one unit per input byte
  # read and per output byte produced, and
  #
  #     allowance = min(base_work + work_per_unit * units, work_ceiling)
  #
  # Decoding charges one operation per unit, plus the Huffman table entries
  # each block header builds, so only streams that spend their input on
  # table rebuilding (thousands of tiny dynamic blocks) approach it.
  #
  # ```
  # limits = Amber::Mica::Deflate::DecodeLimits.custom(max_output_bytes: 1_048_576_i64)
  # limits.max_ratio # => 1_100 (from REQUEST_BODY)
  # ```
  struct DecodeLimits
    # The ratio check starts once a decode has produced this many bytes,
    # so small, highly compressible bodies never trip it.
    RATIO_GRACE_BYTES = 1_048_576_i64

    # The largest history DEFLATE can use (RFC 1951, section 2).
    MAX_WINDOW_BYTES = 32_768

    # Total decoded bytes across every member.
    getter max_output_bytes : Int64
    # Output bytes per input byte consumed, checked once the output passes
    # `RATIO_GRACE_BYTES`. DEFLATE's own ceiling is about 1,032:1.
    getter max_ratio : Int64
    # History a stream may use or declare, at most 32,768 bytes. A zlib
    # header declaring a larger window, or a back reference farther than
    # this, raises `DecodeLimitError`.
    getter max_window_bytes : Int32
    # gzip members per stream (a zlib or raw stream has one).
    getter max_members : Int32
    # gzip FEXTRA, FNAME and FCOMMENT bytes together, per member.
    getter max_metadata_bytes : Int32
    # Work operations allowed per unit (input byte or output byte).
    getter work_per_unit : Int64
    # Work operations allowed regardless of size.
    getter base_work : Int64
    # An absolute cap on work operations, or nil for none.
    getter work_ceiling : Int64?

    def initialize(@max_output_bytes : Int64, @max_ratio : Int64, @max_window_bytes : Int32, @max_members : Int32,
                   @max_metadata_bytes : Int32, @work_per_unit : Int64, @base_work : Int64,
                   @work_ceiling : Int64? = nil)
      check_not_negative("max_output_bytes", @max_output_bytes)
      raise ArgumentError.new("max_ratio must be positive") if @max_ratio < 1
      unless 1 <= @max_window_bytes <= MAX_WINDOW_BYTES
        raise ArgumentError.new("max_window_bytes must be between 1 and #{MAX_WINDOW_BYTES}")
      end
      raise ArgumentError.new("max_members must be positive") if @max_members < 1
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
                    max_members : Int32 = REQUEST_BODY.max_members,
                    max_metadata_bytes : Int32 = REQUEST_BODY.max_metadata_bytes,
                    work_per_unit : Int64 = REQUEST_BODY.work_per_unit,
                    base_work : Int64 = REQUEST_BODY.base_work,
                    work_ceiling : Int64? = REQUEST_BODY.work_ceiling) : self
      new(max_output_bytes, max_ratio, max_window_bytes, max_members, max_metadata_bytes, work_per_unit, base_work,
        work_ceiling)
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
    # `max_document_body_bytes`), 1,100:1, the full 32 KiB window, 64 gzip
    # members, 64 KiB of gzip metadata per member.
    REQUEST_BODY = new(
      max_output_bytes: 8_388_608_i64,
      max_ratio: 1_100_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_members: 64,
      max_metadata_bytes: 65_536,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For response bodies an HTTP client reads from a server it does not
    # control: 64 MiB of output.
    HTTP_CLIENT_RESPONSE = new(
      max_output_bytes: 67_108_864_i64,
      max_ratio: 1_100_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_members: 64,
      max_metadata_bytes: 65_536,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For one WebSocket message (permessage-deflate): 1 MiB of output, one
    # member, no gzip metadata.
    WEBSOCKET_MESSAGE = new(
      max_output_bytes: 1_048_576_i64,
      max_ratio: 1_100_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_members: 1,
      max_metadata_bytes: 0,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )

    # For files the program ships or built itself (precompressed assets):
    # 1 GiB of output, 4,096 members.
    TRUSTED_ASSET = new(
      max_output_bytes: 1_073_741_824_i64,
      max_ratio: 1_100_i64,
      max_window_bytes: MAX_WINDOW_BYTES,
      max_members: 4_096,
      max_metadata_bytes: 1_048_576,
      work_per_unit: 64_i64,
      base_work: 1_000_000_i64,
    )
  end
end
