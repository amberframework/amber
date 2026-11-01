module Amber::Router::Parsers
  # Splits a URL-encoded stream into decoded key and value pairs, the way
  # `URI::Params.parse` does (`&` and `;` separate pairs, `+` is a space),
  # while enforcing the byte limits of `Amber::Configuration::ParamsConfig`
  # as the bytes arrive.
  #
  # The stream is read in blocks no larger than the remaining body
  # allowance, and a raw key or value is rejected once it is longer than
  # three times its decoded limit (percent-encoding uses at most three bytes
  # per decoded byte). Nothing is decoded until its raw form is within
  # bounds; `ParamBudget#admit!` then checks the exact decoded lengths.
  class FormScanner
    private AMPERSAND  = '&'.ord.to_u8
    private SEMICOLON  = ';'.ord.to_u8
    private EQUALS     = '='.ord.to_u8
    private BLOCK_SIZE = 4_096

    @raw_key = IO::Memory.new
    @raw_value = IO::Memory.new
    @in_value = false

    def initialize(@io : IO, @limits : Amber::Configuration::ParamsConfig)
    end

    def each_pair(& : String, String ->) : Nil
      max_body = @limits.max_form_body_bytes.to_i64
      max_raw_key = 3_i64 * @limits.max_key_bytes
      max_raw_value = 3_i64 * @limits.max_value_bytes
      block = Bytes.new(BLOCK_SIZE)
      bytes_read = 0_i64

      loop do
        allowance = max_body - bytes_read
        count = @io.read(block[0, Math.min(BLOCK_SIZE.to_i64, allowance + 1).to_i32])
        break if count == 0

        bytes_read += count
        exceed!("max_form_body_bytes", @limits.max_form_body_bytes) if bytes_read > max_body

        block[0, count].each do |byte|
          if byte == AMPERSAND || byte == SEMICOLON
            finish_pair { |key, value| yield key, value }
          elsif byte == EQUALS && !@in_value
            @in_value = true
          elsif @in_value
            @raw_value.write_byte(byte)
            exceed!("max_value_bytes", @limits.max_value_bytes) if @raw_value.size > max_raw_value
          else
            @raw_key.write_byte(byte)
            exceed!("max_key_bytes", @limits.max_key_bytes) if @raw_key.size > max_raw_key
          end
        end
      end

      finish_pair { |key, value| yield key, value }
    end

    # A segment with no `=` is a key with an empty value; an empty segment
    # is skipped, matching `URI::Params.parse`.
    private def finish_pair(& : String, String ->) : Nil
      if @in_value || @raw_key.size > 0
        key = URI.decode_www_form(@raw_key.to_s)
        value = URI.decode_www_form(@raw_value.to_s)
        yield key, value
      end
      @raw_key.clear
      @raw_value.clear
      @in_value = false
    end

    private def exceed!(limit_name : String, limit_value : Int) : NoReturn
      raise Amber::Exceptions::ParameterLimitExceeded.new(limit_name, limit_value)
    end
  end
end
