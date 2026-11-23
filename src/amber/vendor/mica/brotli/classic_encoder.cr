module Amber::Mica::Brotli
  # The earlier Brotli encoder, which `Encoder` uses for qualities 0 to 4.
  # It turns input into metablocks: LZ77 commands from hash chains
  # (greedy, or lazy at 4) with the four-entry distance cache and static
  # dictionary references, then `MetablockWriter` models and writes them.
  # A metablock that would not be smaller than its bytes is stored
  # uncompressed.
  #
  # | Quality | Matching |
  # |---|---|
  # | 0, 1 | one candidate per hash, greedy |
  # | 2, 3 | hash chains of 4 and 8, distance cache |
  # | 4 | chains of 16, lazy matching, dictionary |
  #
  # :nodoc:
  class ClassicEncoder
    CHAIN_DEPTH   = StaticArray[1, 1, 4, 8, 16, 16, 32, 64, 128, 256, 64, 256]
    HASH_BITS     = StaticArray[14, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17]
    NICE_LENGTH   = StaticArray[16, 32, 32, 48, 64, 96, 128, 192, 258, 512, 325, 325]
    LAZY_MARGIN   = 175
    MIN_LENGTH    =   4
    INITIAL_CACHE = StaticArray[4, 11, 15, 16]
    # The hash chain ring is at most this long (4 MiB of positions).
    MAX_CHAIN = 1 << 20

    getter quality : Int32
    getter window_bits : Int32
    getter max_backward : Int32
    getter metablock_size : Int32

    @finder : MatchFinder
    @cache : StaticArray(Int32, 4) = INITIAL_CACHE
    @commands = [] of Command
    @next_insert = 0
    @dictionary_lookups = 0_i64
    @dictionary_hits = 0_i64
    @header_written = false
    @metablock_writer : MetablockWriter

    # *history_size* bounds the hash chain: the window, or less when the
    # whole input is known to be smaller.
    def initialize(@quality : Int32, @window_bits : Int32, history_size : Int32)
      ClassicEncoder.check(@quality, @window_bits)
      @max_backward = (1 << @window_bits) - 16
      @metablock_size = @quality <= 4 ? 1 << 18 : 1 << 20
      # A small input needs no more hash buckets than about twice its positions.
      size_bits = Math.max(10, 33 - Math.max(history_size, 1).leading_zeros_count)
      hash_bits = Math.min(Math.min(HASH_BITS[@quality], @window_bits + 1), size_bits)
      chain = Math.min(Math.min(history_size, 1 << @window_bits), MAX_CHAIN)
      @finder = MatchFinder.new(hash_bits, chain, CHAIN_DEPTH[@quality])
      @metablock_writer = MetablockWriter.new(@quality)
    end

    def self.check(quality : Int32, window_bits : Int32) : Nil
      raise ArgumentError.new("Brotli quality must be 0 to 11, not #{quality}") unless 0 <= quality <= 11
      raise ArgumentError.new("Brotli window_bits must be 10 to 24, not #{window_bits}") unless 10 <= window_bits <= 24
    end

    # Encodes the whole of *input* into one stream.
    def self.encode(input : Bytes, quality : Int32, window_bits : Int32) : Bytes
      check(quality, window_bits)
      encoder = new(quality, window_bits, Math.max(input.size, 1))
      writer = BitWriter.new(input.size // 2 + 64)
      encoder.encode_block(writer, input, 0, input.size, 0_i64, is_last: true)
      writer.to_slice.dup
    end

    # Encodes `input[start, length]` as metablocks; `input[0, start]` is
    # history the matches may reach (within the window), and
    # *stream_offset* is the stream position of `input[0]`. With *is_last*
    # the stream ends after these bytes.
    def encode_block(writer : BitWriter, input : Bytes, start : Int32, length : Int32,
                     stream_offset : Int64, *, is_last : Bool) : Nil
      write_stream_header(writer)
      if length == 0
        write_last_empty(writer) if is_last
        return
      end
      done = 0
      while done < length
        size = Math.min(@metablock_size, length - done)
        last = is_last && done + size == length
        write_metablock(writer, input, start + done, size, stream_offset, last)
        done += size
      end
      writer.align if is_last
    end

    # Writes an empty metadata metablock and pads to a byte boundary, so
    # everything written so far can be decoded (a flush).
    def write_flush_marker(writer : BitWriter) : Nil
      write_stream_header(writer)
      writer.write(1, 0) # ISLAST
      writer.write(2, 3) # MNIBBLES = 0: metadata
      writer.write(1, 0) # reserved
      writer.write(2, 0) # MSKIPBYTES
      writer.align
    end

    # Rebases stored positions after the writer dropped *offset* bytes.
    def shift(offset : Int32) : Nil
      @finder.shift(offset)
      @next_insert = Math.max(@next_insert - offset, 0)
    end

    private def write_stream_header(writer : BitWriter) : Nil
      return if @header_written
      @header_written = true
      bits = @window_bits
      if bits == 16
        writer.write(1, 0)
      elsif bits == 17
        writer.write(7, 1)
      elsif bits > 17
        writer.write(4, ((bits - 17) << 1) | 1)
      else
        writer.write(7, ((bits - 8) << 4) | 1)
      end
    end

    private def write_last_empty(writer : BitWriter) : Nil
      writer.write(1, 1) # ISLAST
      writer.write(1, 1) # ISLASTEMPTY
      writer.align
    end

    private def write_metablock(writer : BitWriter, input : Bytes, start : Int32, length : Int32,
                                stream_offset : Int64, is_last : Bool) : Nil
      saved_cache = @cache
      parse(input, start, start + length, stream_offset)
      mark = writer.mark
      @metablock_writer.write(writer, input, start, length, @commands, is_last)
      used = writer.bit_size - mark.position
      return if used <= length.to_i64 * 8 + 40
      writer.rewind(mark)
      @cache = saved_cache
      write_uncompressed(writer, input[start, length])
      write_last_empty(writer) if is_last
    end

    private def write_uncompressed(writer : BitWriter, bytes : Bytes) : Nil
      writer.write(1, 0) # ISLAST
      nibbles = EncoderCodes.length_nibbles(bytes.size)
      writer.write(2, nibbles - 4)
      writer.write(nibbles * 4, bytes.size - 1)
      writer.write(1, 1) # ISUNCOMPRESSED
      writer.write_bytes(bytes)
    end

    # --- Greedy and lazy parsing (qualities 0 to 9) ----------------------

    # A match: bytes produced, copy length coded, distance, score, and
    # whether it is a dictionary reference.
    record Match, output : Int32, copy : Int32, distance : Int32, score : Int32, is_dictionary : Bool do
      def self.none : Match
        Match.new(0, 0, 0, MatchFinder::MIN_SCORE, false)
      end
    end

    private def parse(input : Bytes, start : Int32, stop : Int32, stream_offset : Int64) : Nil
      @commands.clear
      position = start
      literal_start = start
      lazy = @quality >= 4
      random_window = @quality >= 9 ? 512 : 64
      while position + MIN_LENGTH <= stop
        insert_until(input, position)
        max_distance = max_distance_at(stream_offset, position)
        match = best_match(input, position, stop - position, max_distance)
        if match.output == 0
          insert_until(input, position + 1)
          run = position - literal_start
          step = 1
          if run > random_window
            step = Math.min(1 + ((run - random_window) >> 5), 8)
            @next_insert = position + step
          end
          position += step
          next
        end
        if lazy
          tries = 0
          while tries < 4 && position + 1 + MIN_LENGTH <= stop
            insert_until(input, position + 1)
            later = best_match(input, position + 1, stop - position - 1, max_distance_at(stream_offset, position + 1))
            break unless later.score >= match.score + LAZY_MARGIN
            match = later
            position += 1
            tries += 1
          end
        end
        emit(position - literal_start, match)
        position += match.output
        literal_start = position
        if @quality <= 1
          @next_insert = Math.max(@next_insert, position - 2)
        end
      end
      emit_tail(stop - literal_start)
    end

    @[AlwaysInline]
    private def max_distance_at(stream_offset : Int64, position : Int32) : Int32
      total = stream_offset + position
      total < @max_backward ? total.to_i32 : @max_backward
    end

    # Adds the positions before *target* to the hash chains.
    @[AlwaysInline]
    private def insert_until(input : Bytes, target : Int32) : Nil
      limit = Math.min(target, input.size - 3)
      while @next_insert < limit
        @finder.insert(input, @next_insert)
        @next_insert += 1
      end
    end

    private def best_match(input : Bytes, position : Int32, limit : Int32, max_distance : Int32) : Match
      best = Match.none
      if @quality >= 2
        slots = @quality >= 4 ? 4 : 1
        slots.times do |slot|
          distance = @cache[slot]
          next if distance > max_distance
          length = MatchFinder.match_length(input, position, position - distance, limit)
          next if length < (slot < 2 ? 2 : 3)
          score = MatchFinder::SCORE_BASE + MatchFinder::LENGTH_WEIGHT * length + (slot == 0 ? 15 : -30 * slot)
          best = Match.new(length, length, distance, score, false) if score > best.score
        end
      end
      length, distance, score = @finder.find(input, position, limit, max_distance, NICE_LENGTH[@quality])
      best = Match.new(length, length, distance, score, false) if length > 0 && score > best.score
      if @quality >= 4 && best.output == 0 && dictionary_worth_trying?
        @dictionary_lookups += 1
        output, word_length, word_id, score = DictionaryMatcher.find(input, position, limit, max_distance, best.score)
        if output > 0
          @dictionary_hits += 1
          best = Match.new(output, word_length, max_distance + 1 + word_id, score, true)
        end
      end
      best
    end

    # Dictionary lookups stop paying once fewer than 1 in 128 finds a
    # word (google/brotli keeps the same ratio).
    private def dictionary_worth_trying? : Bool
      @dictionary_lookups < 128 || @dictionary_hits * 128 >= @dictionary_lookups
    end

    # Adds a command of *insert* literals followed by *match*.
    private def emit(insert : Int32, match : Match) : Nil
      distance = match.distance
      code = match.is_dictionary ? -1 : EncoderCodes.short_distance_code(distance, @cache)
      extra_bits = 0
      extra = 0
      if code < 0
        code, extra_bits, extra = EncoderCodes.distance_symbol(distance)
      end
      insert_code = EncoderCodes.insert_code(insert)
      copy_code = EncoderCodes.copy_code(match.copy)
      symbol = EncoderCodes.command_symbol(insert_code, copy_code, code == 0)
      distance_code = symbol < 128 ? -1 : code
      if !match.is_dictionary && code != 0
        @cache[3] = @cache[2]
        @cache[2] = @cache[1]
        @cache[1] = @cache[0]
        @cache[0] = distance
      end
      @commands << Command.new(insert, match.copy, match.output, symbol, distance_code, extra_bits, extra)
    end

    # Adds the insert-only command that ends a metablock, if any literals
    # are left.
    private def emit_tail(insert : Int32) : Nil
      return if insert == 0
      insert_code = EncoderCodes.insert_code(insert)
      symbol = EncoderCodes.command_symbol(insert_code, 0, true)
      @commands << Command.new(insert, 2, 0, symbol, -1, 0, 0)
    end
  end
end
