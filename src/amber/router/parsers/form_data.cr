module Amber::Router::Parsers
  module FormData
    # Parses a URL-encoded request body, checking each pair as it streams
    # and charging *budget* (the request's own budget by default).
    #
    # A `charset` declared in the `Content-Type` is decoded to UTF-8 while
    # the body streams, as `HTTP::Request#form_params` does in Crystal.
    #
    # Amber parses the form before the action runs (the CSRF pipe reads
    # `_csrf` from `params`), which drains the body. The bytes the parse
    # reads are kept and put back into `request.body`, so the action reads
    # exactly what the client sent. The parse never reads more than
    # `max_form_body_bytes`, which bounds the kept copy; a body whose
    # declared `Content-Length` is already over that limit is rejected
    # without keeping anything.
    def self.parse(request : HTTP::Request, budget : ParamBudget = request.param_budget) : HTTP::Params
      body = request.body
      return HTTP::Params.new unless body

      max_form_body_bytes = budget.limits.max_form_body_bytes.to_i64
      declared_length = declared_content_length(request)
      if declared_length && declared_length > max_form_body_bytes
        return parse_stream(request, body, budget)
      end

      recorder = RecordingReader.new(body, first_block_bytes: RecordingReader.first_block_bytes(declared_length))
      form = parse_stream(request, recorder, budget)
      request.body = recorder.recorded_body
      form
    end

    private def self.parse_stream(request : HTTP::Request, body : IO, budget : ParamBudget) : HTTP::Params
      charset = declared_charset(request)
      return budget.parse_form(body) unless charset

      begin
        # The raw bytes are bounded too, so an encoding that shrinks when
        # decoded (such as UTF-16) cannot carry more than the limit.
        max_form_body_bytes = budget.limits.max_form_body_bytes.to_i64
        raw_body = BoundedIO.new(body, max_form_body_bytes, "max_form_body_bytes")
        raw_body.set_encoding(charset)
        budget.parse_form(UTF8Reader.new(raw_body))
      rescue ArgumentError
        # The message leaves out the client's charset and decoder text.
        raise Amber::Exceptions::BadRequest.new("The form body could not be decoded with its declared charset")
      end
    end

    # The request's `Content-Length` as a non-negative number, or nil when it
    # is missing or not a number.
    private def self.declared_content_length(request : HTTP::Request) : Int64?
      header_value = request.headers["Content-Length"]?
      return unless header_value

      declared_length = header_value.to_i64?
      return unless declared_length
      return if declared_length < 0
      declared_length
    end

    private def self.declared_charset(request : HTTP::Request) : String?
      content_type = request.headers["Content-Type"]?
      return unless content_type
      media_type = MIME::MediaType.parse?(content_type)
      return unless media_type
      media_type["charset"]?
    end

    # Reads *io* and keeps every byte it hands out, so a parsed body can be
    # put back into the request. Whatever reads through it bounds the copy.
    # The first block fits the declared length (at least 512 bytes, at most
    # 64 KiB) and later blocks are 64 KiB, so keeping the bytes allocates
    # about as much as was read, with no growth by doubling.
    private class RecordingReader < IO
      private BLOCK_BYTES          = 65_536
      private SMALLEST_BLOCK       =    512
      private UNKNOWN_LENGTH_BLOCK =  4_096

      @list_of_blocks = [] of Bytes
      @block : Bytes = Bytes.empty
      @block_used = 0

      def initialize(@io : IO, @first_block_bytes : Int32)
      end

      # The first block's size for a body of *declared_length* bytes.
      def self.first_block_bytes(declared_length : Int64?) : Int32
        return UNKNOWN_LENGTH_BLOCK unless declared_length
        declared_length.clamp(SMALLEST_BLOCK.to_i64, BLOCK_BYTES.to_i64).to_i32
      end

      def read(slice : Bytes) : Int32
        count = @io.read(slice)
        keep(slice[0, count])
        count
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("RecordingReader is read-only")
      end

      # A reader over the bytes read so far, from their start.
      def recorded_body : IO
        last_index = @list_of_blocks.size - 1
        list_of_readers = @list_of_blocks.map_with_index do |block, index|
          used = index == last_index ? @block_used : block.size
          IO::Memory.new(block[0, used], writable: false).as(IO)
        end
        ChainedReader.new(list_of_readers)
      end

      private def keep(bytes : Bytes) : Nil
        remaining = bytes
        until remaining.empty?
          if @block_used == @block.size
            @block = Bytes.new(@list_of_blocks.empty? ? @first_block_bytes : BLOCK_BYTES)
            @block_used = 0
            @list_of_blocks << @block
          end
          taken = Math.min(@block.size - @block_used, remaining.size)
          remaining[0, taken].copy_to(@block + @block_used)
          @block_used += taken
          remaining += taken
        end
      end
    end

    # Reads *io* as UTF-8, decoding the encoding set on it.
    private class UTF8Reader < IO
      def initialize(@io : IO)
      end

      def read(slice : Bytes) : Int32
        @io.read_utf8(slice)
      end

      def write(slice : Bytes) : Nil
        raise IO::Error.new("UTF8Reader is read-only")
      end
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
