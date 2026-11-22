module Amber::Mica::Deflate
  # The container around a DEFLATE stream.
  enum Format
    # Raw DEFLATE (RFC 1951).
    Raw
    # zlib (RFC 1950): a two-byte header, DEFLATE data and an Adler-32.
    Zlib
    # gzip (RFC 1952): one or more members, each a header, DEFLATE data, a
    # CRC-32 and the size modulo 2^32.
    Gzip
  end

  # The decoding engine behind `Amber::Mica::Deflate`, `Amber::Mica::Zlib` and
  # `Amber::Mica::Gzip`, one-shot and streaming.
  #
  # Input is pulled: when the decoder needs bits it reads them from its
  # source (a `Bytes` in place, or an `IO` through a buffer of up to
  # 64 KiB), so the only place it stops is a full output buffer, between
  # symbols or inside a back reference or stored block. Output goes into
  # one buffer that also holds the history back references read:
  #
  # - streaming, small reads: the inflater's own buffer holds the 32 KiB
  #   window plus up to 128 KiB of new output; once the reader has taken
  #   the new output, the last 32 KiB slide to the front;
  # - streaming, reads of at least `DIRECT_READ` bytes: the reader's slice
  #   is the output buffer of the run, the history stays in the inflater's
  #   own buffer, and the last 32 KiB of the run are appended to it;
  # - one-shot: the first `STREAM_BUFFER` bytes are decoded in the
  #   inflater's own buffer. A stream that ends there is returned as an
  #   exact-size copy; a longer one moves to a result buffer sized from the
  #   compression ratio it has shown so far (`grow_result`), never past
  #   `max_output_bytes`.
  #
  # Every run of the decoding loop stops at `RUN_BYTES` (the fast loop may
  # pass it by one symbol) and the decoder then settles the work meter, the
  # ratio check and the deadline;
  # the output limit is checked byte-exactly: when the next byte would pass
  # `max_output_bytes` the decode raises `DecodeLimitError` and the byte is
  # never written.
  #
  # Decoding uses a 64-bit bit buffer refilled eight bytes at a time and
  # two-level Huffman tables (`HuffmanTable`), with a fast loop for the
  # stretch where at least `FAST_INPUT_MARGIN` input bytes and
  # `FAST_OUTPUT_MARGIN` bytes of output room remain, and a careful loop
  # for the edges.
  #
  # An inflater keeps its tables and buffers between decodes: `acquire`
  # hands out the spare one (or a new one) and `release` puts it back, so a
  # small body costs no setup allocation.
  #
  # WARNING: An inflater belongs to one fiber at a time.
  #
  # :nodoc:
  class Inflater
    # The DEFLATE window.
    WINDOW = 32_768
    # The longest back reference.
    MAX_MATCH = 258
    # Where a run of the decoding loop aims to stop, so that the work
    # meter, the ratio check and the deadline are settled.
    RUN_BYTES = 65_536
    # Bytes allocated past an output buffer's logical end.
    SLACK = 16
    # The streaming output buffer: the window plus two runs.
    STREAM_BUFFER = WINDOW + 2 * RUN_BYTES
    # The streaming input buffer grows from `INITIAL_INPUT` to this as
    # reads fill it.
    INPUT_BUFFER  = 65_536
    INITIAL_INPUT =  4_096
    # Output buffers start this small and double as output arrives, so a
    # small body costs a small allocation.
    INITIAL_OUTPUT = 4_096
    # A buffer grows (or, streaming at full size, slides) when less room
    # than this remains.
    LOW_ROOM = 1_024

    # Bytes kept before the read position when the input buffer is
    # compacted, so the decoder can hand back up to 7 bytes it loaded into
    # its bit buffer but did not use.
    INPUT_LOOKBACK = 8
    # The streaming decoder refills its input before the fast loop when
    # fewer bytes than this remain.
    INPUT_LOW_WATER = 4_096
    # The fast loop starts a symbol only while this many input bytes
    # remain: a symbol refills the bit buffer at most twice, each refill
    # reads 8 bytes and moves at most 7 forward, and the loop is entered
    # through one more refill.
    FAST_INPUT_MARGIN = 24
    # The fast loop starts a symbol only while this much output room
    # remains: up to 3 literals, a 258-byte back reference and the 32
    # bytes its first copies may write past a short one.
    FAST_OUTPUT_MARGIN = 320
    # A reader's slice of at least this size is decoded into directly
    # (`produce_into`), and only the last 32 KiB are copied aside as
    # history; a smaller one is filled from the inflater's own buffer.
    DIRECT_READ = WINDOW

    # Order of the code length code lengths (RFC 1951, section 3.2.7).
    CODE_LENGTH_ORDER = StaticArray[16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    # The gzip magic bytes (RFC 1952, section 2.3.1).
    MAGIC = StaticArray[0x1F_u8, 0x8B_u8]

    # For a back reference closer than 8 bytes: the smallest multiple of
    # its distance that is at least 8.
    PATTERN_PERIODS = StaticArray[0, 8, 8, 9, 8, 10, 12, 14]

    private enum Phase
      StreamHeader
      BlockHeader
      Stored
      Huffman
      Trailer
      Done
    end

    # The inflater the last decode released, ready for the next one.
    @@spare = Atomic(Inflater?).new(nil)

    # Decoded bytes so far, across every member.
    getter produced : Int64 = 0_i64

    @format : Format = Format::Raw
    @limits : DecodeLimits = DecodeLimits::REQUEST_BODY
    @meter : Core::WorkMeter
    @dictionary : Bytes?
    @one_shot : Bool = true
    # Where gzip member headers are recorded (streaming), or nil.
    @list_of_headers : Array(Gzip::Header)?

    # Input.
    @io : IO?
    @input : UInt8* = Pointer(UInt8).null
    # The streaming input buffer, kept between decodes.
    @input_buffer : Bytes?
    @in_pos : Int32 = 0
    @in_end : Int32 = 0
    @in_base : Int64 = 0_i64
    @io_done : Bool = false
    @bit_buffer : UInt64 = 0_u64
    @bit_count : Int32 = 0

    # Output. `@buffer` is this inflater's own buffer, kept between
    # decodes; `@out` is the buffer in use (`@buffer`, or a one-shot
    # result).
    @buffer : UInt8* = Pointer(UInt8).null
    @buffer_capacity : Int32 = 0
    @out : UInt8* = Pointer(UInt8).null
    @out_capacity : Int32 = 0
    @out_pos : Int32 = 0
    @out_start : Int32 = 0
    @out_checked : Int32 = 0
    @result_start : Int32 = 0
    @lowest_reference : Int32 = 0
    # While a run writes straight into a reader's slice (`produce_into`):
    # the end of the history in the inflater's own buffer and how many
    # bytes before it a back reference may read. Zero bytes otherwise.
    @history_end : UInt8* = Pointer(UInt8).null
    @history_bytes : Int32 = 0
    # Where the current run of the decoding loop aims to stop.
    @run_stop : Int32 = 0
    @window_limit : Int32 = WINDOW

    # Decoding state.
    @phase : Phase = Phase::StreamHeader
    @final_block : Bool = false
    @stored_left : Int32 = 0
    @copy_left : Int32 = 0
    @copy_distance : Int32 = 0
    @literal_length_table : UInt32*
    @literal_length_bits : Int32 = HuffmanTable::FIXED_LITERAL_LENGTH_BITS
    @distance_table : UInt32*
    @distance_bits : Int32 = HuffmanTable::FIXED_DISTANCE_BITS
    # The dynamic tables (literal/length, distance, code length, one
    # allocation), made at the first dynamic block; null before.
    @dynamic_tables : UInt32* = Pointer(UInt32).null
    @lengths = StaticArray(UInt8, 320).new(0_u8)

    # Checks.
    @members : Int32 = 0
    @checksum : UInt32 = 0_u32
    @member_size : UInt32 = 0_u32
    @metered_input : Int64 = 0_i64
    @metered_output : Int64 = 0_i64

    # Returns an inflater started on *source*: the spare one when there
    # is one, a new one otherwise. *list_of_headers* receives each gzip
    # member's header (the streaming readers pass it).
    def self.acquire(source : Bytes | IO, format : Format, limits : DecodeLimits, timeout : Time::Span?,
                     dictionary : Bytes? = nil, list_of_headers : Array(Gzip::Header)? = nil) : Inflater
      inflater = @@spare.swap(nil) || new
      inflater.start(source, format, limits, timeout, dictionary, list_of_headers)
      inflater
    end

    # Decodes the whole of *input* in one call.
    def self.decode(input : Bytes, format : Format, limits : DecodeLimits, timeout : Time::Span?,
                    dictionary : Bytes? = nil) : Bytes
      inflater = acquire(input, format, limits, timeout, dictionary)
      begin
        inflater.decode_all
      ensure
        inflater.release
      end
    end

    protected def initialize
      @meter = Core::WorkMeter.new(Core::WorkBudget.unlimited)
      @literal_length_table = HuffmanTable::FIXED_LITERAL_LENGTH.to_unsafe
      @distance_table = HuffmanTable::FIXED_DISTANCE.to_unsafe
    end

    # Starts a decode of *source*, forgetting the previous one.
    protected def start(source : Bytes | IO, @format : Format, @limits : DecodeLimits, timeout : Time::Span?,
                        @dictionary : Bytes?, @list_of_headers : Array(Gzip::Header)?) : Nil
      @meter.restart(@limits.work_budget(timeout))
      @window_limit = @limits.max_window_bytes
      @produced = 0_i64
      @in_pos = 0
      @in_base = 0_i64
      @bit_buffer = 0_u64
      @bit_count = 0
      @out_pos = 0
      @out_start = 0
      @out_checked = 0
      @result_start = 0
      @lowest_reference = 0
      @phase = Phase::StreamHeader
      @final_block = false
      @stored_left = 0
      @copy_left = 0
      @history_bytes = 0
      @members = 0
      @metered_input = 0_i64
      @metered_output = 0_i64
      if source.is_a?(Bytes)
        @one_shot = true
        @io = nil
        @input = source.to_unsafe
        @in_end = source.size
        @io_done = true
        # A one-shot decode starts in the inflater's own buffer. A small
        # body ends there and is copied out at its exact size; a larger
        # one moves to a result buffer sized from the ratio it has shown
        # by then (`grow_result`). A size the stream declares (gzip
        # ISIZE) is only ever checked, never used to size a buffer.
        use_own_buffer
      else
        @one_shot = false
        @io = source
        buffer = @input_buffer ||= Bytes.new(GC.malloc_atomic(INITIAL_INPUT).as(UInt8*), INITIAL_INPUT)
        @input = buffer.to_unsafe
        @in_end = 0
        @io_done = false
        use_own_buffer
      end
      @meter.enforce_deadline("while decoding") { position }
    end

    private def use_own_buffer : Nil
      if @buffer.null?
        @buffer = GC.malloc_atomic((INITIAL_OUTPUT + SLACK).to_u64).as(UInt8*)
        @buffer_capacity = INITIAL_OUTPUT
      end
      @out = @buffer
      @out_capacity = @buffer_capacity
    end

    # Ends this inflater's decode and makes it the spare one. The caller
    # must not use it again.
    def release : Nil
      @io = nil
      @input = Pointer(UInt8).null
      @in_end = 0
      @dictionary = nil
      @list_of_headers = nil
      @out = @buffer
      @out_capacity = @buffer_capacity
      @phase = Phase::Done
      @@spare.set(self)
    end

    # Decodes the whole stream and returns its output (one-shot only).
    def decode_all : Bytes
      while produce
      end
      size = @out_pos - @result_start
      return Bytes.empty if size == 0
      working = @out
      # A result buffer that the ratio sized well is the result. One that
      # is more than half too large (a stream whose first part compressed
      # far better than the rest) is copied out at its exact size and
      # freed, like the inflater's own buffer, so a result never holds more
      # than one and a half times its size.
      if working != @buffer && @out_capacity - @result_start <= size.to_i64 + size // 2 + LOW_ROOM
        return Bytes.new(working + @result_start, size)
      end
      result = GC.malloc_atomic(size.to_u64).as(UInt8*)
      result.copy_from(working + @result_start, size)
      unless working == @buffer
        @out = @buffer
        @out_capacity = @buffer_capacity
        GC.free(working.as(Void*))
      end
      Bytes.new(result, size)
    end

    # Returns the decoded bytes the caller has not taken yet (streaming).
    def pending : Bytes
      Bytes.new(@out + @out_start, @out_pos - @out_start)
    end

    # Marks *count* pending bytes as taken.
    def take(count : Int32) : Nil
      @out_start += count
    end

    # Returns true when the stream ended and every check passed.
    def done? : Bool
      @phase.done?
    end

    # Decodes until new output is pending or the stream ends. Returns false
    # once the stream has ended (and its trailers have been checked).
    def produce : Bool
      before = @produced
      loop do
        case @phase
        in .stream_header?
          read_stream_header
        in .block_header?
          read_block_header
        in .stored?, .huffman?
          limit, capped = prepare_output
          if @phase.stored?
            if @run_stop < limit
              copy_stored(@run_stop, false)
            else
              copy_stored(limit, capped)
            end
          else
            decode_huffman(limit, capped)
          end
          settle
          return true if @produced > before
        in .trailer?
          read_trailer
        in .done?
          return @produced > before
        end
      end
    end

    # Decodes straight into *slice* (at least `DIRECT_READ` bytes, and
    # nothing may be pending) until bytes are there or the stream ends.
    # Returns the bytes written; 0 once the stream has ended (and its
    # trailers have been checked).
    def produce_into(slice : Bytes) : Int32
      loop do
        case @phase
        in .stream_header?
          read_stream_header
        in .block_header?
          read_block_header
        in .stored?, .huffman?
          count = run_into(slice)
          return count if count > 0
        in .trailer?
          read_trailer
        in .done?
          return 0
        end
      end
    end

    # One run of the decoding loop with *slice* as the output buffer. The
    # history stays in the inflater's own buffer, where back references
    # that reach before the slice read it; afterwards the last 32 KiB of
    # the run join it.
    private def run_into(slice : Bytes) : Int32
      own_pos = @out_pos
      own_lowest = @lowest_reference
      @history_end = @buffer + own_pos
      @history_bytes = Math.min(own_pos - own_lowest, WINDOW)
      @out = slice.to_unsafe
      @out_capacity = slice.size
      @out_pos = 0
      @out_start = 0
      @out_checked = 0
      @lowest_reference = 0
      count = 0
      begin
        @run_stop = RUN_BYTES
        allowed = @limits.max_output_bytes - @produced
        capped = allowed <= slice.size
        limit = capped ? allowed.to_i32 : slice.size
        if @phase.stored?
          if @run_stop < limit
            copy_stored(@run_stop, false)
          else
            copy_stored(limit, capped)
          end
        else
          decode_huffman(limit, capped)
        end
        settle
        count = @out_pos
      ensure
        @history_bytes = 0
        @out = @buffer
        @out_capacity = @buffer_capacity
        @out_pos = own_pos
        @out_start = own_pos
        @out_checked = own_pos
        @lowest_reference = own_lowest
      end
      keep_history(slice.to_unsafe + count, count) if count > 0
      count
    end

    # Appends the last bytes of a run that wrote *count* bytes ending at
    # *run_end* to the history in the inflater's own buffer (at most 32 KiB
    # of history matter).
    private def keep_history(run_end : UInt8*, count : Int32) : Nil
      if count >= WINDOW
        reserve_own_buffer(WINDOW)
        @buffer.copy_from(run_end - WINDOW, WINDOW)
        @out_pos = WINDOW
        @lowest_reference = 0
      else
        if @out_pos + count > @buffer_capacity
          # Keep only the history still in reach, at the front.
          kept = Math.min(@out_pos - @lowest_reference, WINDOW - count)
          @buffer.move_from(@buffer + (@out_pos - kept), kept)
          @out_pos = kept
          @lowest_reference = 0
          reserve_own_buffer(kept + count)
        end
        (@buffer + @out_pos).copy_from(run_end - count, count)
        @out_pos += count
      end
      @out_start = @out_pos
      @out_checked = @out_pos
    end

    # Makes the inflater's own buffer at least *bytes* large (at most
    # `STREAM_BUFFER`), keeping what it holds.
    private def reserve_own_buffer(bytes : Int32) : Nil
      return if bytes <= @buffer_capacity
      wanted = @buffer_capacity
      while wanted < bytes
        wanted *= 2
      end
      wanted = STREAM_BUFFER if wanted > STREAM_BUFFER
      @buffer = GC.realloc(@buffer.as(Void*), (wanted + SLACK).to_u64).as(UInt8*)
      @buffer_capacity = wanted
      @out = @buffer
      @out_capacity = wanted
    end

    # The byte of the source the decoder has reached.
    private def input_offset : Int64
      @in_base + @in_pos - (@bit_count >> 3)
    end

    private def position : Core::Position
      Core::Position.new(input_offset)
    end

    private def malformed(message : String) : NoReturn
      raise MalformedStreamError.new(message, position)
    end

    private def truncated(where : String) : NoReturn
      raise TruncatedStreamError.new("Input ends inside #{where}", position)
    end

    private def limit_exceeded(limit : String, message : String) : NoReturn
      raise DecodeLimitError.new(message, position, limit)
    end

    # ---- input ----

    # Reads more input into the buffer (streaming). Returns false at the
    # end of the source.
    private def refill_input : Bool
      io = @io
      buffer = @input_buffer
      return false if @io_done || io.nil? || buffer.nil?
      keep_from = @in_pos - INPUT_LOOKBACK
      keep_from = 0 if keep_from < 0
      if keep_from > 0
        kept = @in_end - keep_from
        buffer.to_unsafe.move_from(buffer.to_unsafe + keep_from, kept)
        @in_base += keep_from
        @in_pos -= keep_from
        @in_end = kept
      end
      # Once the stream has outrun the buffer, double it (up to
      # INPUT_BUFFER): small bodies keep a small buffer, long streams get
      # large reads.
      if buffer.size < INPUT_BUFFER && @in_base + @in_end >= buffer.size
        grown = Bytes.new(GC.malloc_atomic(buffer.size.to_u64 * 2).as(UInt8*), buffer.size * 2)
        grown.copy_from(buffer.to_unsafe, @in_end)
        @input_buffer = buffer = grown
        @input = grown.to_unsafe
      end
      count = io.read(buffer[@in_end, buffer.size - @in_end])
      @meter.enforce_deadline("while decoding") { position }
      if count == 0
        @io_done = true
        return false
      end
      @in_end += count
      true
    end

    # Returns true when a streaming decoder should read more before its
    # fast loop: fewer than `INPUT_LOW_WATER` bytes (or a quarter of a
    # smaller buffer) remain and the source has not ended.
    private def input_running_low? : Bool
      buffer = @input_buffer
      return false if buffer.nil? || @io_done
      @in_end - @in_pos < Math.min(INPUT_LOW_WATER, buffer.size // 4)
    end

    # Makes sure the bit buffer holds at least *count* bits (at most 56).
    # Returns false when the source ends first.
    private def need_bits(count : Int32) : Bool
      while @bit_count < count
        if @in_pos == @in_end
          return false unless refill_input
        end
        @bit_buffer |= @input[@in_pos].to_u64.unsafe_shl(@bit_count)
        @in_pos += 1
        @bit_count += 8
      end
      true
    end

    # Takes *count* bits (at most 32), raising `TruncatedStreamError` with
    # *where* when the source ends first.
    private def take_bits(count : Int32, where : String) : UInt32
      truncated(where) unless need_bits(count)
      value = (@bit_buffer & (1_u64.unsafe_shl(count) &- 1)).to_u32!
      @bit_buffer = @bit_buffer.unsafe_shr(count)
      @bit_count -= count
      value
    end

    # Drops the bits up to the next byte boundary and hands the whole bytes
    # still in the bit buffer back to the input.
    private def align_to_byte : Nil
      drop = @bit_count & 7
      @bit_buffer = @bit_buffer.unsafe_shr(drop)
      @bit_count -= drop
      @in_pos -= @bit_count >> 3
      @bit_buffer = 0_u64
      @bit_count = 0
    end

    # Reads one byte (the bit buffer must be empty).
    private def read_byte(where : String) : UInt8
      if @in_pos == @in_end
        truncated(where) unless refill_input
      end
      byte = @input[@in_pos]
      @in_pos += 1
      byte
    end

    private def read_u16_le(where : String) : UInt32
      read_byte(where).to_u32 | (read_byte(where).to_u32 << 8)
    end

    private def read_u32_le(where : String) : UInt32
      read_u16_le(where) | (read_u16_le(where) << 16)
    end

    # Returns true when no input byte remains (the bit buffer must be
    # empty).
    private def at_input_end? : Bool
      return false if @in_pos < @in_end
      !refill_input
    end

    # ---- output ----

    # Makes room for the next run and returns the index it may write up to
    # and whether that index is `max_output_bytes` (so that writing past it
    # must raise rather than wait for room).
    private def prepare_output : {Int32, Bool}
      if @out_capacity - @out_pos < LOW_ROOM
        if @one_shot
          if @out == @buffer && @out_capacity < STREAM_BUFFER
            grow_own_buffer
          else
            grow_result
          end
        elsif @buffer_capacity < STREAM_BUFFER
          grow_own_buffer
        else
          slide_window
        end
      end
      # The run aims to stop RUN_BYTES from here (the fast loop may pass
      # that by one symbol); the room in the buffer and `max_output_bytes`
      # are hard limits.
      @run_stop = @out_pos + RUN_BYTES
      space = @out_capacity - @out_pos
      allowed = @limits.max_output_bytes - @produced
      if allowed <= space
        {@out_pos + allowed.to_i32, true}
      else
        {@out_pos + space, false}
      end
    end

    # Doubles the inflater's own buffer, up to `STREAM_BUFFER`.
    private def grow_own_buffer : Nil
      wanted = @buffer_capacity * 2
      wanted = STREAM_BUFFER if wanted > STREAM_BUFFER
      @buffer = GC.realloc(@buffer.as(Void*), (wanted + SLACK).to_u64).as(UInt8*)
      @buffer_capacity = wanted
      @out = @buffer
      @out_capacity = wanted
    end

    # Moves a one-shot decode to a larger result buffer: the size the
    # ratio so far predicts for the whole input plus an eighth, between
    # one and a quarter and eight times the buffer it leaves, never past
    # `max_output_bytes`. Eight times at most, because the ratio of a
    # stream's first bytes says little about a long stream: each move
    # predicts from more of it, and the buffer it leaves is freed at once,
    # so only the last one weighs on the collector.
    private def grow_result : Nil
      ceiling = @limits.max_output_bytes + @result_start
      consumed = input_offset
      consumed = 1_i64 if consumed < 1
      predicted = (@out_pos - @result_start).to_i64 * @in_end // consumed
      wanted = predicted + predicted // 8 + LOW_ROOM + @result_start
      capacity = @out_capacity.to_i64
      wanted = capacity + capacity // 4 if wanted < capacity + capacity // 4
      wanted = capacity * 8 if wanted > capacity * 8
      wanted = ceiling if wanted > ceiling
      wanted = Int32::MAX.to_i64 - SLACK if wanted > Int32::MAX - SLACK
      return if wanted <= @out_capacity
      grown = GC.malloc_atomic((wanted + SLACK).to_u64).as(UInt8*)
      grown.copy_from(@out, @out_pos)
      GC.free(@out.as(Void*)) unless @out == @buffer
      @out = grown
      @out_capacity = wanted.to_i32
    end

    # Moves the last 32 KiB of output to the front of the streaming buffer
    # (the reader has taken everything before `@out_pos`).
    private def slide_window : Nil
      shift = @out_pos - WINDOW
      @out.move_from(@out + shift, WINDOW)
      @out_pos -= shift
      @out_start -= shift
      @out_checked -= shift
      @lowest_reference = Math.max(@lowest_reference - shift, 0)
    end

    # Settles a run: updates the member checksum and size over the new
    # output, then the work meter, the ratio check and the deadline.
    private def settle : Nil
      new_bytes = @out_pos - @out_checked
      if new_bytes > 0
        start = @out + @out_checked
        case @format
        in .zlib? then @checksum = Adler32.update(@checksum, start, new_bytes)
        in .gzip? then @checksum = CRC32.update(@checksum, start, new_bytes)
        in .raw?
        end
        @member_size &+= new_bytes.to_u32!
        @produced += new_bytes
        @out_checked = @out_pos
      end
      meter_progress
    end

    private def meter_progress : Nil
      consumed = input_offset
      delta = (consumed - @metered_input) + (@produced - @metered_output)
      @metered_input = consumed
      @metered_output = @produced
      if delta > 0
        @meter.add_units(delta)
        @meter.enforce("while decoding") { position } if @meter.charge(delta)
      end
      if @produced > DecodeLimits::RATIO_GRACE_BYTES && @produced > @limits.max_ratio &* Math.max(consumed, 1_i64)
        limit_exceeded("max_ratio", "Output grew past max_ratio (#{@limits.max_ratio}:1): #{@produced} bytes from #{consumed}")
      end
    end

    private def charge_work(count : Int32) : Nil
      @meter.enforce("while decoding") { position } if @meter.charge(count)
    end

    # ---- containers ----

    private def read_stream_header : Nil
      case @format
      in .raw?
        start_member
      in .zlib?
        read_zlib_header
      in .gzip?
        read_gzip_header
      end
      @phase = Phase::BlockHeader
    end

    private def start_member : Nil
      @members += 1
      if @members > @limits.max_members
        limit_exceeded("max_members", "More than max_members (#{@limits.max_members}) members")
      end
      @lowest_reference = @out_pos
      @final_block = false
      @member_size = 0_u32
      @checksum = @format.zlib? ? 1_u32 : 0_u32
    end

    private def read_zlib_header : Nil
      start_member
      cmf = read_byte("the zlib header")
      flg = read_byte("the zlib header")
      malformed("Incorrect zlib header check") unless (cmf.to_u32 * 256 + flg) % 31 == 0
      malformed("Unknown compression method #{cmf & 0x0F} in the zlib header") unless cmf & 0x0F == 8
      window_bits = (cmf >> 4).to_i32 + 8
      malformed("Invalid window size in the zlib header (CINFO #{cmf >> 4})") if window_bits > 15
      if (1 << window_bits) > @limits.max_window_bytes
        limit_exceeded("max_window_bytes", "The zlib header declares a #{1 << window_bits}-byte window, over max_window_bytes (#{@limits.max_window_bytes})")
      end
      return unless flg & 0x20 != 0
      expected = (read_byte("the dictionary id").to_u32 << 24) | (read_byte("the dictionary id").to_u32 << 16) |
                 (read_byte("the dictionary id").to_u32 << 8) | read_byte("the dictionary id").to_u32
      dictionary = @dictionary
      malformed("The stream needs a preset dictionary") unless dictionary
      unless Adler32.update(1_u32, dictionary) == expected
        raise ChecksumError.new("The preset dictionary does not match the stream's dictionary id", position)
      end
      load_dictionary(dictionary)
    end

    # Places the last 32 KiB of *dictionary* in the history before the
    # output (it is history only: not output, not checksummed).
    private def load_dictionary(dictionary : Bytes) : Nil
      used = dictionary.size > WINDOW ? dictionary[dictionary.size - WINDOW, WINDOW] : dictionary
      charge_work(used.size)
      needed = @out_pos + used.size + LOW_ROOM
      if needed > @out_capacity
        if @out == @buffer
          # Room for the history plus a first run in the inflater's own
          # buffer (at its full size it always has it).
          needed = STREAM_BUFFER
          @buffer = GC.realloc(@buffer.as(Void*), (needed + SLACK).to_u64).as(UInt8*)
          @buffer_capacity = needed
          @out = @buffer
        else
          @out = GC.realloc(@out.as(Void*), (needed + SLACK).to_u64).as(UInt8*)
        end
        @out_capacity = needed
      end
      (@out + @out_pos).copy_from(used.to_unsafe, used.size)
      @lowest_reference = @out_pos
      @out_pos += used.size
      @out_start = @out_pos
      @out_checked = @out_pos
      @result_start = @out_pos if @one_shot
    end

    private def read_gzip_header : Nil
      header_storage = uninitialized StaticArray(UInt8, 10)
      header = header_storage.to_slice
      header.size.times do |index|
        header[index] = read_byte("the gzip header")
        # Each byte is judged as it arrives, as zlib does.
        if index < 2 && header[index] != MAGIC[index]
          malformed(@members > 0 ? "Trailing data after the last gzip member" : "Not a gzip stream (bad magic bytes)")
        end
        malformed("Unknown compression method #{header[2]} in the gzip header") if index == 2 && header[2] != 8
        malformed("Reserved gzip header flags are set") if index == 3 && header[3] & 0xE0 != 0
      end
      start_member
      flags = header[3]
      # Only a header with FHCRC needs its CRC.
      header_crc = flags & 0x02 != 0 ? CRC32.update(0_u32, header) : 0_u32
      metadata = 0
      extra_field = nil
      if flags & 0x04 != 0
        length_bytes = Bytes[read_byte("FEXTRA"), read_byte("FEXTRA")]
        header_crc = CRC32.update(header_crc, length_bytes)
        length = length_bytes[0].to_i32 | (length_bytes[1].to_i32 << 8)
        metadata = add_metadata(metadata, length)
        extra = Bytes.new(length)
        length.times { |index| extra[index] = read_byte("FEXTRA") }
        header_crc = CRC32.update(header_crc, extra)
        extra_field = extra
      end
      file_name = nil
      if flags & 0x08 != 0
        file_name, metadata, header_crc = read_zero_terminated("FNAME", metadata, header_crc)
      end
      comment = nil
      if flags & 0x10 != 0
        comment, metadata, header_crc = read_zero_terminated("FCOMMENT", metadata, header_crc)
      end
      if flags & 0x02 != 0
        stored = read_u16_le("FHCRC")
        unless stored == header_crc & 0xFFFF
          raise ChecksumError.new("The gzip header CRC (FHCRC) does not match", position)
        end
      end
      list_of_headers = @list_of_headers
      return unless list_of_headers
      list_of_headers << Gzip::Header.new(
        modification_time: header[4].to_u32 | (header[5].to_u32 << 8) | (header[6].to_u32 << 16) | (header[7].to_u32 << 24),
        extra_flags: header[8], operating_system: header[9], is_text: flags & 0x01 != 0,
        extra_field: extra_field, file_name: file_name, comment: comment)
    end

    private def add_metadata(metadata : Int32, count : Int32) : Int32
      total = metadata + count
      if total > @limits.max_metadata_bytes
        limit_exceeded("max_metadata_bytes", "gzip header fields pass max_metadata_bytes (#{@limits.max_metadata_bytes})")
      end
      charge_work(count)
      total
    end

    private def read_zero_terminated(field : String, metadata : Int32, header_crc : UInt32) : {Bytes, Int32, UInt32}
      bytes = IO::Memory.new
      loop do
        byte = read_byte(field)
        header_crc = CRC32.update(header_crc, pointerof(byte), 1)
        break if byte == 0
        metadata = add_metadata(metadata, 1)
        bytes.write_byte(byte)
      end
      {bytes.to_slice, metadata, header_crc}
    end

    private def read_trailer : Nil
      align_to_byte
      case @format
      in .raw?
        nil
      in .zlib?
        stored = read_u32_le("the Adler-32 trailer").byte_swap
        raise ChecksumError.new("Adler-32 mismatch", position) unless stored == @checksum
      in .gzip?
        stored_crc = read_u32_le("the CRC-32 trailer")
        raise ChecksumError.new("CRC-32 mismatch", position) unless stored_crc == @checksum
        stored_size = read_u32_le("the ISIZE trailer")
        raise ChecksumError.new("ISIZE mismatch", position) unless stored_size == @member_size
        unless at_input_end?
          @phase = Phase::StreamHeader
          return
        end
      end
      malformed("Trailing data after the end of the stream") unless at_input_end?
      @phase = Phase::Done
    end

    # ---- blocks ----

    private def read_block_header : Nil
      if @final_block
        @phase = Phase::Trailer
        return
      end
      meter_progress
      charge_work(1)
      header = take_bits(3, "a block header")
      @final_block = header & 1 == 1
      case header >> 1
      when 0
        align_to_byte
        length = read_u16_le("a stored block header")
        complement = read_u16_le("a stored block header")
        malformed("Stored block length does not match its complement") unless length == (~complement & 0xFFFF)
        @stored_left = length.to_i32
        @phase = Phase::Stored
      when 1
        @literal_length_table = HuffmanTable::FIXED_LITERAL_LENGTH.to_unsafe
        @literal_length_bits = HuffmanTable::FIXED_LITERAL_LENGTH_BITS
        @distance_table = HuffmanTable::FIXED_DISTANCE.to_unsafe
        @distance_bits = HuffmanTable::FIXED_DISTANCE_BITS
        @phase = Phase::Huffman
      when 2
        read_dynamic_tables
        @phase = Phase::Huffman
      else
        malformed("Invalid block type 3")
      end
    end

    private def read_dynamic_tables : Nil
      counts = take_bits(14, "a dynamic block header")
      literal_count = (counts & 31).to_i32 + 257
      distance_count = ((counts >> 5) & 31).to_i32 + 1
      code_length_count = (counts >> 10).to_i32 + 4
      if literal_count > 286 || distance_count > 30
        malformed("Too many length or distance symbols (HLIT #{literal_count}, HDIST #{distance_count})")
      end
      if @dynamic_tables.null?
        entries = HuffmanTable::LITERAL_LENGTH_ENTRIES + HuffmanTable::DISTANCE_ENTRIES +
                  HuffmanTable::CODE_LENGTH_ENTRIES
        # Not cleared: the builder writes every entry a lookup can reach.
        @dynamic_tables = GC.malloc_atomic(entries.to_u64 * sizeof(UInt32)).as(UInt32*)
      end
      literal_length_table = @dynamic_tables
      distance_table = literal_length_table + HuffmanTable::LITERAL_LENGTH_ENTRIES
      code_length_table = distance_table + HuffmanTable::DISTANCE_ENTRIES
      lengths = @lengths.to_unsafe
      19.times { |index| lengths[index] = 0_u8 }
      # The first 18 code length code lengths fit one fill of the bit
      # buffer (54 bits); a source that ends inside them is read bit by bit.
      index = 0
      together = code_length_count < 18 ? code_length_count : 18
      if need_bits(together * 3)
        bits = @bit_buffer
        while index < together
          lengths[CODE_LENGTH_ORDER[index]] = (bits & 7).to_u8!
          bits >>= 3
          index += 1
        end
        @bit_buffer = bits
        @bit_count -= together * 3
      end
      while index < code_length_count
        lengths[CODE_LENGTH_ORDER[index]] = take_bits(3, "the code length code").to_u8
        index += 1
      end
      code_length_bits = build_table(code_length_table, HuffmanTable::CODE_LENGTH_ENTRIES, lengths, 19,
        HuffmanTable::CODE_LENGTH_ROOT, HuffmanTable::Alphabet::CodeLength, "code length")

      total = literal_count + distance_count
      index = read_code_lengths_fast(code_length_table, code_length_bits, lengths, total)
      code_length_mask = (1_u64 << code_length_bits) - 1
      while index < total
        entry = decode_careful(code_length_table, code_length_mask, code_length_bits, "the code lengths", "code length")
        symbol = (entry >> 16).to_i32
        if symbol < 16
          lengths[index] = symbol.to_u8
          index += 1
          next
        end
        if symbol == 16
          malformed("Repeat code 16 with no previous length") if index == 0
          value = lengths[index - 1]
          repeat = 3 + take_bits(2, "the code lengths").to_i32
        elsif symbol == 17
          value = 0_u8
          repeat = 3 + take_bits(3, "the code lengths").to_i32
        else
          value = 0_u8
          repeat = 11 + take_bits(7, "the code lengths").to_i32
        end
        malformed("Code length repeat runs past the code lengths") if index + repeat > total
        repeat.times do
          lengths[index] = value
          index += 1
        end
      end
      malformed("The literal/length code has no end-of-block code") if lengths[256] == 0
      @literal_length_bits = build_table(literal_length_table, HuffmanTable::LITERAL_LENGTH_ENTRIES, lengths, literal_count,
        HuffmanTable::LITERAL_LENGTH_ROOT, HuffmanTable::Alphabet::LiteralLength, "literal/length")
      @distance_bits = build_table(distance_table, HuffmanTable::DISTANCE_ENTRIES, lengths + literal_count, distance_count,
        HuffmanTable::DISTANCE_ROOT, HuffmanTable::Alphabet::Distance, "distance")
      @literal_length_table = literal_length_table
      @distance_table = distance_table
      charge_work(total)
    end

    # Reads code lengths into *lengths* while whole 8-byte loads of input
    # remain, and returns how many it read. It stops before any symbol it
    # cannot finish (too little input, an invalid code, a repeat that has
    # no previous length or runs past *total*), leaving that symbol to the
    # careful loop, which raises the error.
    private def read_code_lengths_fast(table : UInt32*, table_bits : Int32, lengths : UInt8*, total : Int32) : Int32
      input = @input
      in_pos = @in_pos
      in_stop = @in_end - 8
      bit_buffer = @bit_buffer
      bit_count = @bit_count
      mask = (1_u64 << table_bits) - 1
      index = 0
      while index < total
        # A symbol takes at most 7 code bits and 7 extra bits.
        if bit_count < 14
          break if in_pos > in_stop
          bit_buffer |= load_u64(input + in_pos).unsafe_shl(bit_count)
          in_pos &+= (63 &- bit_count) >> 3
          bit_count |= 56
        end
        entry = table[(bit_buffer & mask).to_u32!]
        break if entry & HuffmanTable::EXCEPTIONAL != 0
        symbol = (entry >> 16).to_i32!
        code_bits = (entry & 0xFF).to_i32!
        if symbol < 16
          bit_buffer = bit_buffer.unsafe_shr(code_bits)
          bit_count &-= code_bits
          lengths[index] = symbol.to_u8!
          index &+= 1
          next
        end
        extra = bit_buffer.unsafe_shr(code_bits)
        if symbol == 16
          break if index == 0
          value = lengths[index &- 1]
          repeat = 3 &+ (extra & 3).to_i32!
          code_bits &+= 2
        elsif symbol == 17
          value = 0_u8
          repeat = 3 &+ (extra & 7).to_i32!
          code_bits &+= 3
        else
          value = 0_u8
          repeat = 11 &+ (extra & 127).to_i32!
          code_bits &+= 7
        end
        break if index &+ repeat > total
        bit_buffer = bit_buffer.unsafe_shr(code_bits)
        bit_count &-= code_bits
        stop = index &+ repeat
        while index < stop
          lengths[index] = value
          index &+= 1
        end
      end
      @in_pos = in_pos
      @bit_count = bit_count
      # Clear the bits above the count that an 8-byte load brought in.
      @bit_buffer = bit_buffer & (1_u64.unsafe_shl(bit_count) &- 1)
      index
    end

    # Builds *table* and returns the bits that index its root.
    private def build_table(table : UInt32*, capacity : Int32, lengths : UInt8*, count : Int32, root : Int32,
                            alphabet : HuffmanTable::Alphabet, name : String) : Int32
      built = HuffmanTable.build(table, capacity, lengths, count, root, alphabet)
      case built.problem
      in .oversubscribed? then malformed("Oversubscribed #{name} code")
      in .incomplete?     then malformed("Incomplete #{name} code")
      in .none?
      end
      charge_work(built.work)
      built.table_bits
    end

    # Decodes one entry of *table* bit by bit with refills from the source.
    # Raises at an invalid code or when the source ends inside the code.
    # The returned entry's code bits are consumed (not its extra bits).
    private def decode_careful(table : UInt32*, mask : UInt64, root : Int32, where : String, code_name : String,
                               with_extra : Bool = false) : UInt32
      need_bits(15)
      entry = table[@bit_buffer & mask]
      if entry & HuffmanTable::SUBTABLE != 0
        truncated(where) if @bit_count < root
        @bit_buffer = @bit_buffer.unsafe_shr(root)
        @bit_count -= root
        sub_mask = (1_u64.unsafe_shl((entry >> 8) & 0xF)) &- 1
        entry = table[(entry >> 16) + (@bit_buffer & sub_mask)]
      end
      length = (entry & 0xFF).to_i32
      # A length or distance entry: consume its code bits only; the caller
      # takes the extra bits.
      length = ((entry >> 8) & 0xF).to_i32 if with_extra && entry & (HuffmanTable::LITERAL | HuffmanTable::EXCEPTIONAL) == 0
      if entry & HuffmanTable::EXCEPTIONAL != 0 && entry & HuffmanTable::END_OF_BLOCK == 0
        # Judged once the bits of the unused pattern are in, as zlib does.
        truncated(where) if length > @bit_count
        malformed("Invalid #{code_name} code")
      end
      truncated(where) if length > @bit_count
      @bit_buffer = @bit_buffer.unsafe_shr(length)
      @bit_count -= length
      entry
    end

    # Copies stored-block bytes up to *limit*.
    private def copy_stored(limit : Int32, capped : Bool) : Nil
      while @stored_left > 0
        if @out_pos == limit
          output_limit_reached if capped
          return
        end
        if @in_pos == @in_end
          truncated("a stored block") unless refill_input
        end
        count = Math.min(@stored_left, Math.min(@in_end - @in_pos, limit - @out_pos))
        (@out + @out_pos).copy_from(@input + @in_pos, count)
        @out_pos += count
        @in_pos += count
        @stored_left -= count
      end
      @phase = Phase::BlockHeader
    end

    private def output_limit_reached : NoReturn
      limit_exceeded("max_output_bytes", "Output would pass max_output_bytes (#{@limits.max_output_bytes})")
    end

    # Decodes Huffman-coded symbols until the end of the block, the run's
    # stop or *limit*.
    private def decode_huffman(limit : Int32, capped : Bool) : Nil
      loop do
        if @copy_left > 0
          return unless finish_copy(limit, capped)
        end
        return if @out_pos >= @run_stop
        if input_running_low?
          refill_input
        end
        if @in_end - @in_pos >= FAST_INPUT_MARGIN && limit - @out_pos >= FAST_OUTPUT_MARGIN
          decode_fast(limit)
          return unless @phase.huffman?
          next
        end
        return unless decode_one_careful(limit, capped)
        return unless @phase.huffman?
      end
    end

    # Finishes a back reference that the last run stopped inside. Returns
    # false when *limit* stopped it again.
    private def finish_copy(limit : Int32, capped : Bool) : Bool
      while @copy_left > 0
        if @out_pos == limit
          output_limit_reached if capped
          return false
        end
        # A reference that reaches before a reader's slice reads the history.
        @out[@out_pos] = @copy_distance > @out_pos ? @history_end[@out_pos - @copy_distance] : @out[@out_pos - @copy_distance]
        @out_pos += 1
        @copy_left -= 1
      end
      true
    end

    # Decodes one symbol at the edges of the input or the output. Returns
    # false when the run must stop (no room before *limit*).
    private def decode_one_careful(limit : Int32, capped : Bool) : Bool
      if @out_pos == limit && !capped
        return false
      end
      # With 48 bits in the bit buffer a whole symbol is there (15 code
      # and 5 extra bits of a length, 15 and 13 of a distance), so it is
      # decoded without a check per step.
      while @bit_count <= 56 && @in_pos < @in_end
        @bit_buffer |= @input[@in_pos].to_u64.unsafe_shl(@bit_count)
        @in_pos += 1
        @bit_count += 8
      end
      if @bit_count >= 48 && @out_pos < limit
        return true if decode_whole_symbol(limit, capped)
      end
      decode_one_step_by_step(limit, capped)
    end

    # Decodes one symbol from a bit buffer that holds all of it. Returns
    # false, taking nothing, at anything that raises (an invalid code, a
    # distance too far back), which the step-by-step decode then reports.
    private def decode_whole_symbol(limit : Int32, capped : Bool) : Bool
      bits = @bit_buffer
      table = @literal_length_table
      entry = table[(bits & (1_u64.unsafe_shl(@literal_length_bits) &- 1)).to_u32!]
      used = 0_u32
      if entry & HuffmanTable::SUBTABLE != 0
        used = entry & 0xFF
        bits = bits.unsafe_shr(used)
        entry = table[(entry >> 16) &+ (bits.to_u32! & (1_u32.unsafe_shl((entry >> 8) & 0xF) &- 1))]
      end
      if entry & HuffmanTable::LITERAL != 0
        used &+= entry & 0xFF
        @out[@out_pos] = (entry >> 16).to_u8!
        @out_pos += 1
      elsif entry & HuffmanTable::EXCEPTIONAL != 0
        return false if entry & HuffmanTable::END_OF_BLOCK == 0
        used &+= entry & 0xFF
        @phase = Phase::BlockHeader
      else
        total = entry & 0xFF
        length = ((entry >> 16) &+ (bits & (1_u64.unsafe_shl(total) &- 1)).unsafe_shr((entry >> 8) & 0xF)).to_i32!
        used &+= total
        bits = bits.unsafe_shr(total)
        table = @distance_table
        entry = table[(bits & (1_u64.unsafe_shl(@distance_bits) &- 1)).to_u32!]
        if entry & HuffmanTable::SUBTABLE != 0
          used &+= entry & 0xFF
          bits = bits.unsafe_shr(entry & 0xFF)
          entry = table[(entry >> 16) &+ (bits.to_u32! & (1_u32.unsafe_shl((entry >> 8) & 0xF) &- 1))]
        end
        return false if entry & HuffmanTable::EXCEPTIONAL != 0
        total = entry & 0xFF
        distance = ((entry >> 16) &+ (bits & (1_u64.unsafe_shl(total) &- 1)).unsafe_shr((entry >> 8) & 0xF)).to_i32!
        used &+= total
        return false if distance > @out_pos - @lowest_reference + @history_bytes || distance > @window_limit
        @bit_buffer = @bit_buffer.unsafe_shr(used)
        @bit_count -= used.to_i32!
        @copy_left = length
        @copy_distance = distance
        # The copy stops at *limit* and the run with it (or the decode
        # raises, when *limit* is the output limit).
        finish_copy(limit, capped)
        return true
      end
      @bit_buffer = @bit_buffer.unsafe_shr(used)
      @bit_count -= used.to_i32!
      true
    end

    # Decodes one symbol with full checks at every step. Returns false when
    # the run must stop (no room before *limit*).
    private def decode_one_step_by_step(limit : Int32, capped : Bool) : Bool
      entry = decode_careful(@literal_length_table, (1_u64 << @literal_length_bits) - 1, @literal_length_bits,
        "a Huffman block", "literal/length", with_extra: true)
      if entry & HuffmanTable::LITERAL != 0
        output_limit_reached if @out_pos == limit
        @out[@out_pos] = (entry >> 16).to_u8!
        @out_pos += 1
        return true
      end
      if entry & HuffmanTable::END_OF_BLOCK != 0
        @phase = Phase::BlockHeader
        return true
      end
      length = (entry >> 16).to_i32 + take_bits(extra_bits_of(entry), "a length").to_i32
      distance_entry = decode_careful(@distance_table, (1_u64 << @distance_bits) - 1, @distance_bits, "a distance",
        "distance", with_extra: true)
      malformed("Invalid distance code") if distance_entry & HuffmanTable::EXCEPTIONAL != 0
      distance = (distance_entry >> 16).to_i32 + take_bits(extra_bits_of(distance_entry), "a distance").to_i32
      check_distance(distance)
      @copy_left = length
      @copy_distance = distance
      finish_copy(limit, capped)
    end

    # The extra bits of a length or distance entry.
    private def extra_bits_of(entry : UInt32) : Int32
      ((entry & 0xFF) - ((entry >> 8) & 0xF)).to_i32
    end

    private def check_distance(distance : Int32) : Nil
      if distance > @out_pos - @lowest_reference + @history_bytes
        malformed("Invalid distance too far back (#{distance})")
      end
      if distance > @window_limit
        limit_exceeded("max_window_bytes", "Back reference of #{distance} bytes passes max_window_bytes (#{@window_limit})")
      end
    end

    @[AlwaysInline]
    private def load_u64(pointer : UInt8*) : UInt64
      value = uninitialized UInt64
      pointerof(value).as(UInt8*).copy_from(pointer, 8)
      {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::LittleEndian %}
        value = value.byte_swap
      {% end %}
      value
    end

    # Refills the fast loop's bit buffer from *in_next* with one 8-byte
    # load, leaving at least 56 bits. Only the low byte of *bits_left* is
    # the bit count: the fast loop subtracts whole table entries from it
    # and never looks at the rest.
    private macro refill_fast_bits
      bit_buffer |= load_u64(in_next).unsafe_shl(bits_left & 63)
      in_next += 7_u32 &- ((bits_left >> 3) & 7)
      bits_left |= 56_u32
    end

    # Takes the code (and extra) bits of *entry* from the bit buffer,
    # keeping the buffer as it was in *saved*.
    private macro consume_fast_entry
      saved = bit_buffer
      bit_buffer = bit_buffer.unsafe_shr(entry & 63)
      bits_left &-= entry
    end

    # The fast loop: runs while at least `FAST_INPUT_MARGIN` input bytes
    # and `FAST_OUTPUT_MARGIN` bytes of output room remain (the caller
    # checks both before the first symbol), so it refills the bit buffer
    # with 8-byte loads and copies back references in 16-byte steps without
    # bounds checks. The next literal/length entry is looked up before the
    # current symbol's bytes are written, so the lookup and the copy
    # overlap. Leaves through the end of the block or its bounds; the
    # careful loop takes over at the edges.
    #
    # Never inlined: compiled on its own, the loop keeps its state in
    # registers whatever calls it.
    @[NoInline]
    private def decode_fast(limit : Int32) : Nil
      in_next = @input + @in_pos
      in_stop = @input + (@in_end - FAST_INPUT_MARGIN)
      out_base = @out
      out_next = out_base + @out_pos
      stop = limit - FAST_OUTPUT_MARGIN
      stop = @run_stop if @run_stop < stop
      out_stop = out_base + stop
      lowest = out_base + @lowest_reference
      window = @window_limit.to_u32!
      history_bytes = @history_bytes.to_i64
      # From a place in the slice to the same place counted back from the
      # end of the history.
      history_shift = @history_end - lowest
      bit_buffer = @bit_buffer
      bits_left = @bit_count.to_u32!
      literal_lengths = @literal_length_table
      literal_length_mask = 1_u64.unsafe_shl(@literal_length_bits) &- 1
      distances = @distance_table
      distance_mask = 1_u64.unsafe_shl(@distance_bits) &- 1
      saved = 0_u64
      problem = 0
      far_distance = 0

      refill_fast_bits
      entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
      loop do
        consume_fast_entry
        if entry & HuffmanTable::LITERAL != 0
          # Up to two more literals before the next refill: a literal
          # found in the root table takes at most 10 bits, and 56 are in.
          literal = (entry >> 16).to_u8!
          entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
          consume_fast_entry
          out_next.value = literal
          out_next += 1
          if entry & HuffmanTable::LITERAL != 0
            literal = (entry >> 16).to_u8!
            entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
            consume_fast_entry
            out_next.value = literal
            out_next += 1
            if entry & HuffmanTable::LITERAL != 0
              out_next.value = (entry >> 16).to_u8!
              out_next += 1
              entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
              refill_fast_bits
              break unless in_next <= in_stop && out_next <= out_stop
              next
            end
          end
        end

        if entry & HuffmanTable::EXCEPTIONAL != 0
          if entry & HuffmanTable::END_OF_BLOCK != 0
            @phase = Phase::BlockHeader
            break
          end
          if entry & HuffmanTable::SUBTABLE == 0
            # An unused bit pattern: give its bits back for the error.
            bit_buffer = saved
            bits_left &+= entry & 0xFF
            problem = 1
            break
          end
          entry = literal_lengths[(entry >> 16) &+ (bit_buffer.to_u32! & (1_u32.unsafe_shl((entry >> 8) & 0xF) &- 1))]
          consume_fast_entry
          if entry & HuffmanTable::LITERAL != 0
            out_next.value = (entry >> 16).to_u8!
            out_next += 1
            entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
            refill_fast_bits
            break unless in_next <= in_stop && out_next <= out_stop
            next
          end
          if entry & HuffmanTable::EXCEPTIONAL != 0
            if entry & HuffmanTable::END_OF_BLOCK != 0
              @phase = Phase::BlockHeader
            else
              bit_buffer = saved
              bits_left &+= entry & 0xFF
              problem = 1
            end
            break
          end
        end

        # A length: its extra bits sit above the code bits in *saved*.
        length = ((entry >> 16) &+ (saved & (1_u64.unsafe_shl(entry & 63) &- 1)).unsafe_shr((entry >> 8) & 0xF)).to_i32!
        entry = distances[(bit_buffer & distance_mask).to_u32!]
        # After the distance the next literal/length entry is looked up
        # from the bits still in the buffer, so its lookup does not wait
        # for a refill: a distance found in the root table takes up to 21
        # bits (28 through a subtable) and the lookup 10 more. Two
        # literals and a length may have left as few as 16.
        if bits_left & 0xFF < 31
          refill_fast_bits
        end
        if entry & HuffmanTable::EXCEPTIONAL != 0
          if entry & HuffmanTable::SUBTABLE == 0
            problem = 2
            break
          end
          if bits_left & 0xFF < 38
            refill_fast_bits
          end
          bit_buffer = bit_buffer.unsafe_shr(entry & 63)
          bits_left &-= entry
          entry = distances[(entry >> 16) &+ (bit_buffer.to_u32! & (1_u32.unsafe_shl((entry >> 8) & 0xF) &- 1))]
          if entry & HuffmanTable::EXCEPTIONAL != 0
            problem = 2
            break
          end
        end
        consume_fast_entry
        distance = ((entry >> 16) &+ (saved & (1_u64.unsafe_shl(entry & 63) &- 1)).unsafe_shr((entry >> 8) & 0xF)).to_u32!
        behind = out_next - lowest
        if distance.to_i64! > behind &+ history_bytes || distance > window
          problem = 3
          far_distance = distance.to_i32!
          break
        end

        # A reference that reaches before a reader's slice starts in the
        # history: the same copy, from a source moved there. Chosen
        # without a branch, since in a slice's first 32 KiB either is as
        # likely as the other.
        is_far = distance.to_i64! > behind
        destination = out_next
        source = out_next + (0_i64 &- distance.to_i64!)
        source += history_shift if is_far
        if is_far & ((distance < 16) | (length.to_i64! > distance.to_i64! &- behind))
          # Rare: the reference runs on from the history into the slice,
          # or sits in the slice's first bytes. Byte by byte.
          from_history = distance.to_i64! &- behind
          copied = 0_i64
          while copied < length
            out_next.value = copied < from_history ? source[copied] : lowest[copied &- from_history]
            out_next += 1
            copied &+= 1
          end
          entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
          refill_fast_bits
          break unless in_next <= in_stop && out_next <= out_stop
          next
        end
        out_next += length
        # Look the next symbol up before copying, so the two overlap.
        entry = literal_lengths[(bit_buffer & literal_length_mask).to_u32!]
        refill_fast_bits
        if distance >= 16
          destination.copy_from(source, 16)
          (destination + 16).copy_from(source + 16, 16)
          if length > 32
            copied = 32_i64
            length = length.to_i64!
            while copied < length
              (destination + copied).copy_from(source + copied, 16)
              copied &+= 16
            end
          end
        elsif distance >= 8
          destination.copy_from(source, 8)
          (destination + 8).copy_from(source + 8, 8)
          (destination + 16).copy_from(source + 16, 8)
          (destination + 24).copy_from(source + 24, 8)
          if length > 32
            copied = 32_i64
            length = length.to_i64!
            while copied < length
              (destination + copied).copy_from(source + copied, 8)
              copied &+= 8
            end
          end
        elsif distance == 1
          # A run of one byte.
          run = source.value.to_u64 &* 0x0101_0101_0101_0101_u64
          store_u64(destination, run)
          store_u64(destination + 8, run)
          store_u64(destination + 16, run)
          store_u64(destination + 24, run)
          if length > 32
            copied = 32_i64
            length = length.to_i64!
            while copied < length
              store_u64(destination + copied, run)
              copied &+= 8
            end
          end
        else
          # Write the first repetitions of the pattern a byte at a time,
          # until a whole multiple of it (its period, at least 8 bytes)
          # sits behind the copy; then copy 8 bytes at a time from one
          # period back.
          period = PATTERN_PERIODS.to_unsafe[distance]
          first = length < period ? length : period
          copied = 0
          while copied < first
            destination[copied] = source[copied]
            copied &+= 1
          end
          source = destination - period
          while copied < length
            (destination + copied).copy_from(source + copied, 8)
            copied &+= 8
          end
        end
        break unless in_next <= in_stop && out_next <= out_stop
      end

      @in_pos = (in_next - @input).to_i32!
      @out_pos = (out_next - out_base).to_i32!
      bit_count = (bits_left & 0xFF).to_i32!
      @bit_count = bit_count
      # Clear the bits above the count that the 8-byte refill loaded
      # (they repeat the next input byte).
      @bit_buffer = bit_buffer & (1_u64.unsafe_shl(bit_count) &- 1)
      case problem
      when 1 then malformed("Invalid literal/length code")
      when 2 then malformed("Invalid distance code")
      when 3 then check_distance(far_distance)
      end
    end

    @[AlwaysInline]
    private def store_u64(pointer : UInt8*, value : UInt64) : Nil
      {% if IO::ByteFormat::SystemEndian != IO::ByteFormat::LittleEndian %}
        value = value.byte_swap
      {% end %}
      pointer.copy_from(pointerof(value).as(UInt8*), 8)
    end
  end
end
