module Amber::Mica::Brotli
  # The Brotli encoder (RFC 7932) behind `Brotli.encode` and
  # `Brotli::Writer`.
  #
  # From quality 5 to 9 it follows google/brotli 1.2.1's libbrotlienc
  # (see `Encode`): input is cut into blocks of 64 KiB (256 KiB at
  # quality 9); each block is searched with a hash table of recent
  # positions, the distance cache and the static dictionary; the
  # commands of consecutive blocks gather into one metablock of up to
  # 8 MiB, which is split greedily into block types, given static literal
  # context maps when the UTF-8 byte classes predict each other, and
  # written with run-length-friendly prefix codes. A metablock that would
  # not be smaller than its bytes is stored uncompressed.
  #
  # Qualities 10 and 11 follow libbrotlienc too: a binary tree of
  # positions finds every match length, an optimal parse (one pass at 10,
  # two at 11) picks the commands by estimated bits, the distance code
  # parameters are chosen per metablock, and literals, commands and
  # distances are split into block types and clustered, with literal
  # context maps from the UTF-8 or signed context model. Qualities 0 to 4
  # use `ClassicEncoder`.
  #
  # :nodoc:
  class Encoder
    alias Hasher = Encode::LongestMatchHasher(4, 1) | Encode::LongestMatchHasher(5, 1) |
                   Encode::LongestMatchHasher(4, 0) | Encode::LongestMatchHasher(5, 0)

    INITIAL_CACHE = StaticArray[4, 11, 15, 16]

    getter quality : Int32
    getter window_bits : Int32

    @classic : ClassicEncoder?
    @hasher : Hasher?
    @tree_hasher : Encode::BinaryTreeHasher?
    @size_hint : Int64
    @block_bits : Int32
    @params = Encode::DistanceParams.new(0_u32, 0_u32)
    @cache = StaticArray(Int32, 16).new(0)
    @saved_cache = StaticArray(Int32, 4).new(0)
    @commands = Encode::CommandBuffer.new
    @arena = Encode::Arena.new
    @num_literals = 0_i64
    @last_insert_length = 0
    @header_written = false
    @hasher_prepared = false

    # *history_size* is the input size when it is known up front (one
    # encode), else the window.
    def initialize(@quality : Int32, @window_bits : Int32, history_size : Int32)
      Encoder.check(@quality, @window_bits)
      @size_hint = history_size.to_i64
      @block_bits = @quality >= 9 && @window_bits > 16 ? Math.min(18, @window_bits) : 16
      4.times { |slot| @cache[slot] = INITIAL_CACHE[slot] }
      4.times { |slot| @saved_cache[slot] = INITIAL_CACHE[slot] }
      @classic = ClassicEncoder.new(@quality, @window_bits, history_size) unless ported?
    end

    # The most input the streaming writer buffers into one metablock: 256 KiB
    # below quality 5, 1 MiB from 5.
    def self.metablock_size(quality : Int32) : Int32
      quality <= 4 ? 1 << 18 : 1 << 20
    end

    def self.check(quality : Int32, window_bits : Int32) : Nil
      raise ArgumentError.new("Brotli quality must be 0 to 11, not #{quality}") unless 0 <= quality <= 11
      raise ArgumentError.new("Brotli window_bits must be 10 to 24, not #{window_bits}") unless 10 <= window_bits <= 24
    end

    # Encodes the whole of *input* into one stream.
    def self.encode(input : Bytes, quality : Int32, window_bits : Int32) : Bytes
      check(quality, window_bits)
      encoder = new(quality, window_bits, Math.max(input.size, 1))
      writer = BitWriter.new(2 * input.size + 600)
      encoder.encode_block(writer, input, 0, input.size, 0_i64, is_last: true)
      encoder.release
      writer.to_slice.dup
    end

    # How much input the streaming writer buffers before encoding it.
    def metablock_size : Int32
      Encoder.metablock_size(@quality)
    end

    # Encodes `input[start, length]`; `input[0, start]` is history the
    # matches may reach (within the window), and *stream_offset* is the
    # stream position of `input[0]`. With *is_last* the stream ends after
    # these bytes; without, everything given is written out (a flush
    # point) but the stream stays open.
    def encode_block(writer : BitWriter, input : Bytes, start : Int32, length : Int32,
                     stream_offset : Int64, *, is_last : Bool) : Nil
      if classic = @classic
        classic.encode_block(writer, input, start, length, stream_offset, is_last: is_last)
        return
      end
      write_stream_header(writer)
      if length == 0
        if is_last
          writer.write(2, 3)
          writer.align
        end
        return
      end
      data = input.to_unsafe
      metablock_start = start
      position = start
      stop = start + length
      block_size = 1 << @block_bits
      max_metablock = 1 << Math.min(1 + Math.max(@window_bits, @block_bits), 24)
      while position < stop
        bytes = Math.min(block_size, stop - position)
        last_block = position + bytes == stop
        process_block(input, position, bytes, last_block && is_last, stream_offset)
        position += bytes
        processed = position - metablock_start
        fits = processed + block_size <= max_metablock
        if !last_block && fits && @num_literals < max_metablock // 8 && @commands.size < max_metablock // 8
          next
        end
        if @last_insert_length > 0
          @commands.push(Encode::Command.insert_only(@last_insert_length.to_u32))
          @num_literals += @last_insert_length
          @last_insert_length = 0
        end
        write_metablock(writer, data, metablock_start, position - metablock_start, last_block && is_last)
        metablock_start = position
        @commands.clear
        @num_literals = 0
        4.times { |slot| @saved_cache[slot] = @cache[slot] }
      end
    end

    # Writes an empty metadata metablock and pads to a byte boundary, so
    # everything written so far can be decoded (a flush).
    def write_flush_marker(writer : BitWriter) : Nil
      if classic = @classic
        classic.write_flush_marker(writer)
        return
      end
      write_stream_header(writer)
      writer.write(1, 0) # ISLAST
      writer.write(2, 3) # MNIBBLES = 0: metadata
      writer.write(1, 0) # reserved
      writer.write(2, 0) # MSKIPBYTES
      writer.align
    end

    # Rebases stored positions after the writer dropped *offset* bytes.
    def shift(offset : Int32) : Nil
      if classic = @classic
        classic.shift(offset)
        return
      end
      # Positions in the hash tables are buffer indexes; after a shift
      # they would point at the wrong bytes, so start the tables over.
      @hasher_prepared = false
    end

    # Frees the hash tables now rather than when the encoder is collected.
    def release : Nil
      if hasher = @hasher
        hasher.release
        @hasher = nil
      end
      if tree_hasher = @tree_hasher
        tree_hasher.release
        @tree_hasher = nil
      end
      @arena.release
    end

    private def ported? : Bool
      @quality >= 5
    end

    private def hasher : Hasher
      @hasher ||= begin
        large = @size_hint >= (1 << 20) && @window_bits >= 19
        block_bits = @quality - 1
        bucket_bits = @quality < 7 ? 14 : 15
        last_distances = @quality < 7 ? 4 : (@quality < 9 ? 10 : 16)
        if @quality <= 6
          large ? Encode::LongestMatchHasher(5, 1).new(15, block_bits, last_distances) : Encode::LongestMatchHasher(4, 1).new(bucket_bits, block_bits, last_distances)
        else
          large ? Encode::LongestMatchHasher(5, 0).new(15, block_bits, last_distances) : Encode::LongestMatchHasher(4, 0).new(bucket_bits, block_bits, last_distances)
        end
      end
    end

    # Finds the commands of `input[position, bytes]` (google/brotli's
    # EncodeData, up to the metablock decision).
    private def process_block(input : Bytes, position : Int32, bytes : Int32, is_last : Bool, stream_offset : Int64) : Nil
      if @quality >= 10
        process_block_optimally(input, position, bytes, is_last, stream_offset)
        return
      end
      data = input.to_unsafe
      current = hasher
      unless @hasher_prepared
        one_shot = position == 0 && stream_offset == 0 && is_last
        current.prepare(one_shot, bytes, data + position, input.size - position)
        @hasher_prepared = true
      end
      current.stitch_to_previous_block(bytes, position, data) if position + bytes - 3 + current.hash_type_length <= input.size + 3
      if @commands.size > 0 && @last_insert_length == 0
        position, bytes = extend_last_command(data, position, bytes, stream_offset)
      end
      # One branch per hasher type, so each search loop is compiled for
      # its own hasher.
      @last_insert_length, literals = case current
                                      when Encode::LongestMatchHasher(4, 1)
                                        find_commands(current, data, position, bytes, stream_offset)
                                      when Encode::LongestMatchHasher(5, 1)
                                        find_commands(current, data, position, bytes, stream_offset)
                                      when Encode::LongestMatchHasher(4, 0)
                                        find_commands(current, data, position, bytes, stream_offset)
                                      else
                                        find_commands(current, data, position, bytes, stream_offset)
                                      end
      @num_literals += literals
    end

    # Qualities 10 and 11: the binary tree hasher and the optimal parse
    # (google/brotli's EncodeData with BrotliCreateZopfliBackwardReferences
    # or BrotliCreateHqZopfliBackwardReferences).
    private def process_block_optimally(input : Bytes, position : Int32, bytes : Int32, is_last : Bool,
                                        stream_offset : Int64) : Nil
      data = input.to_unsafe
      tree = @tree_hasher ||= Encode::BinaryTreeHasher.new(@window_bits,
        position == 0 && stream_offset == 0 && is_last, bytes)
      unless @hasher_prepared
        tree.prepare
        @hasher_prepared = true
      end
      tree.stitch_to_previous_block(bytes, position, data)
      if @commands.size > 0 && @last_insert_length == 0
        position, bytes = extend_last_command(data, position, bytes, stream_offset)
      end
      @last_insert_length, literals = if @quality == 10
                                        Encode::Zopfli.create_backward_references(bytes, position, data, @quality,
                                          @window_bits, stream_offset, @params, tree, @cache.to_unsafe,
                                          @last_insert_length, @commands)
                                      else
                                        Encode::Zopfli.create_hq_backward_references(bytes, position, data, @quality,
                                          @window_bits, stream_offset, @params, tree, @cache.to_unsafe,
                                          @last_insert_length, @commands)
                                      end
      @num_literals += literals
    end

    private def find_commands(hasher : H, data : UInt8*, position : Int32, bytes : Int32, stream_offset : Int64) : {Int32, Int64} forall H
      Encode.create_backward_references(hasher, @quality, @window_bits, data, position, bytes, stream_offset,
        @params, @cache.to_unsafe, @last_insert_length, @commands)
    end

    # Lengthens the last command's copy into the new block while the
    # bytes keep matching (google/brotli's ExtendLastCommand).
    private def extend_last_command(data : UInt8*, position : Int32, bytes : Int32, stream_offset : Int64) : {Int32, Int32}
      last = @commands.last
      max_backward = (1_i64 << @window_bits) - Encode::WINDOW_GAP
      copy_field = last.copy_field
      last_copy = (copy_field & 0x1FFFFFF).to_i64
      max_distance = Math.min(position + stream_offset - last_copy, max_backward)
      max_distance = Math.min(max_distance, position.to_i64 - last_copy)
      distance = @cache[0].to_i64
      code = last.restore_distance_code(@params)
      if code < Encode::NUM_DISTANCE_SHORT_CODES || code.to_i64 - (Encode::NUM_DISTANCE_SHORT_CODES - 1) == distance
        if distance <= max_distance && distance > 0
          while bytes != 0 && data[position] == data[position - distance]
            copy_field &+= 1
            bytes -= 1
            position += 1
          end
        end
        copy = ((copy_field & 0x1FFFFFF).to_i32 &+ (copy_field >> 25).to_i32).to_u32!
        symbol = Encode.length_code(last.insert_length, copy, last.distance_prefix & 0x3FF == 0)
        @commands[@commands.size - 1] = Encode::Command.new(last.insert_length, copy_field, last.distance_extra,
          symbol, last.distance_prefix)
      end
      {position, bytes}
    end

    # google/brotli's WriteMetaBlockInternal from quality 5.
    private def write_metablock(writer : BitWriter, data : UInt8*, start : Int32, bytes : Int32, is_last : Bool) : Nil
      unless should_compress?(data, start, bytes)
        restore_cache
        Encode::MetablockStore.store_uncompressed(is_last, data, start, bytes, writer)
        return
      end
      mark = writer.mark
      previous_byte = start >= 1 ? data[start - 1] : 0_u8
      previous_byte2 = start >= 2 ? data[start - 2] : 0_u8
      if @quality >= 10
        mode = Encode::LiteralCost.mostly_utf8?(data + start, bytes) ? Encode::CONTEXT_UTF8 : Encode::CONTEXT_SIGNED
        metablock, params = Encode::MetablockBuilder.build(data, start, previous_byte, previous_byte2, @commands,
          @params, mode, @quality, @arena)
      else
        mode = Encode::CONTEXT_UTF8
        params = @params
        num_contexts, context_map = Encode::MetablockBuilder.decide_over_literal_context_modeling(data, start, bytes,
          @quality, @size_hint)
        metablock = Encode::MetablockBuilder.build_greedy(data, start, previous_byte, previous_byte2, num_contexts,
          context_map, @commands, @arena)
      end
      Encode::MetablockBuilder.optimize_histograms(params.alphabet_size.to_i32, metablock, @arena)
      Encode::MetablockStore.store(data, start, bytes, previous_byte, previous_byte2, is_last, params,
        mode, @commands, metablock, @arena, writer)
      @arena.reset
      used = writer.bit_size - mark.position + (mark.position & 7)
      if bytes + 4 < (used >> 3)
        writer.rewind(mark)
        restore_cache
        Encode::MetablockStore.store_uncompressed(is_last, data, start, bytes, writer)
      end
    end

    private def restore_cache : Nil
      4.times { |slot| @cache[slot] = @saved_cache[slot] }
    end

    # Whether a metablock with these commands is worth compressing: not
    # when it is almost all literals of near-random bytes (google/brotli's
    # ShouldCompress).
    private def should_compress?(data : UInt8*, start : Int32, bytes : Int32) : Bool
      return false if bytes <= 2
      if @commands.size < (bytes >> 8) + 2 && @num_literals.to_f64 > 0.99 * bytes
        histogram = StaticArray(UInt32, 256).new(0_u32)
        samples = (bytes + 12) // 13
        position = start
        samples.times do
          histogram[data[position]] += 1
          position += 13
        end
        return false if Encode.bits_entropy(histogram.to_unsafe, 256) > bytes * 7.92 / 13
      end
      true
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
  end
end
