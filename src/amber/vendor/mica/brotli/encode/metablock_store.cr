module Amber::Mica::Brotli::Encode
  # Writes one category's block switches and symbols with the prefix
  # code of the current block type (google/brotli's BlockEncoder).
  class BlockEncoder
    # Code tables, all from the metablock arena.
    @type_depths : Pointer(UInt8)
    @type_bits : Pointer(UInt16)
    @length_depths : Pointer(UInt8)
    @length_bits : Pointer(UInt16)
    @last_type = 1
    @second_last_type = 0
    @block_index = 0
    @block_length : UInt32
    @entropy_index = 0
    @depths = Pointer(UInt8).null
    @bits = Pointer(UInt16).null

    def initialize(@histogram_length : Int32, @split : BlockSplit, @arena : Arena)
      @type_depths = @arena.alloc_cleared(UInt8, 258)
      @type_bits = @arena.alloc_cleared(UInt16, 258)
      @length_depths = @arena.alloc_cleared(UInt8, 26)
      @length_bits = @arena.alloc_cleared(UInt16, 26)
      @block_length = @split.num_blocks == 0 ? 0_u32 : @split.lengths[0]
    end

    @[AlwaysInline]
    private def next_type_code(type : Int32) : Int32
      code = type == @last_type &+ 1 ? 1 : (type == @second_last_type ? 0 : type &+ 2)
      @second_last_type = @last_type
      @last_type = type
      code
    end

    private def store_block_switch(length : UInt32, type : Int32, first : Bool, writer : BitWriter) : Nil
      type_code = next_type_code(type)
      writer.write(@type_depths[type_code], @type_bits[type_code]) unless first
      length_code = Encode.block_length_prefix_code(length)
      writer.write(@length_depths[length_code], @length_bits[length_code])
      writer.write(BLOCK_LENGTH_NBITS[length_code], length &- BLOCK_LENGTH_OFFSET[length_code])
    end

    # Stores NBLTYPES and, with several types, the type and count codes
    # and the first count (google/brotli's BuildAndStoreBlockSplitCode).
    def store_block_switch_codes(tree : HuffmanNode*, writer : BitWriter) : Nil
      num_types = @split.num_types
      type_histogram = StaticArray(UInt32, 258).new(0_u32)
      length_histogram = StaticArray(UInt32, 26).new(0_u32)
      last = 1
      second_last = 0
      @split.num_blocks.times do |i|
        type = @split.types[i].to_i32!
        code = type == last &+ 1 ? 1 : (type == second_last ? 0 : type &+ 2)
        second_last = last
        last = type
        type_histogram[code] &+= 1 if i != 0
        length_histogram[Encode.block_length_prefix_code(@split.lengths[i])] &+= 1
      end
      MetablockStore.store_var_len_uint8(num_types &- 1, writer)
      return unless num_types > 1
      Entropy.build_and_store(type_histogram.to_unsafe, num_types &+ 2, num_types &+ 2, tree,
        @type_depths, @type_bits, writer)
      Entropy.build_and_store(length_histogram.to_unsafe, NUM_BLOCK_LENGTH_SYMBOLS, NUM_BLOCK_LENGTH_SYMBOLS, tree,
        @length_depths, @length_bits, writer)
      store_block_switch(@split.lengths[0], @split.types[0].to_i32!, true, writer)
    end

    # Builds and stores the prefix code of each of *histograms*.
    def store_entropy_codes(histograms : HistogramSet, alphabet_size : Int32, tree : HuffmanNode*, writer : BitWriter) : Nil
      table_size = histograms.count &* @histogram_length
      @depths = @arena.alloc(UInt8, table_size)
      @bits = @arena.alloc(UInt16, table_size)
      histograms.count.times do |i|
        offset = i &* @histogram_length
        Entropy.build_and_store(histograms[i], @histogram_length, alphabet_size, tree,
          @depths + offset, @bits + offset, writer)
      end
    end

    @[AlwaysInline]
    private def switch_block(writer : BitWriter, context_bits : Int32?) : Nil
      @block_index &+= 1
      length = @split.lengths[@block_index]
      type = @split.types[@block_index].to_i32!
      @block_length = length
      @entropy_index = context_bits ? type << context_bits : type &* @histogram_length
      store_block_switch(length, type, false, writer)
    end

    @[AlwaysInline]
    def store_symbol(symbol : Int, writer : BitWriter) : Nil
      switch_block(writer, nil) if @block_length == 0
      @block_length &-= 1
      index = @entropy_index &+ symbol
      writer.write(@depths[index], @bits[index])
    end

    @[AlwaysInline]
    def store_symbol_with_context(symbol : Int, context : Int, context_map : UInt32*, context_bits : Int32,
                                  writer : BitWriter) : Nil
      switch_block(writer, context_bits) if @block_length == 0
      @block_length &-= 1
      histogram = context_map[@entropy_index &+ context].to_i32!
      index = histogram &* @histogram_length &+ symbol
      writer.write(@depths[index], @bits[index])
    end
  end

  # Writes metablocks (google/brotli's brotli_bit_stream.c).
  module MetablockStore
    def self.store_var_len_uint8(n : Int32, writer : BitWriter) : Nil
      if n == 0
        writer.write(1, 0)
      else
        bits = Encode.log2_floor(n.to_u32!).to_i32!
        writer.write(1, 1)
        writer.write(3, bits)
        writer.write(bits, n &- (1 << bits))
      end
    end

    # MNIBBLES - 4, the MLEN - 1 bit count and MLEN - 1.
    private def self.encode_mlen(length : Int32) : {Int32, Int32, Int32}
      lg = length == 1 ? 1 : Encode.log2_floor((length &- 1).to_u32!).to_i32! &+ 1
      nibbles = (lg < 16 ? 16 : lg &+ 3) // 4
      {nibbles &- 4, nibbles &* 4, length &- 1}
    end

    def self.store_compressed_header(is_last : Bool, length : Int32, writer : BitWriter) : Nil
      writer.write(1, is_last ? 1 : 0)
      writer.write(1, 0) if is_last
      nibbles, bit_count, value = encode_mlen(length)
      writer.write(2, nibbles)
      writer.write(bit_count, value)
      writer.write(1, 0) unless is_last
    end

    # Stores `data[start, length]` as an uncompressed metablock; with
    # *is_last* an empty last metablock follows.
    def self.store_uncompressed(is_last : Bool, data : UInt8*, start : Int32, length : Int32, writer : BitWriter) : Nil
      writer.write(1, 0)
      nibbles, bit_count, value = encode_mlen(length)
      writer.write(2, nibbles)
      writer.write(bit_count, value)
      writer.write(1, 1)
      writer.write_bytes(Slice.new(data + start, length))
      if is_last
        writer.write(1, 1)
        writer.write(1, 1)
        writer.align
      end
    end

    private def self.move_to_front_transform(input : Slice(UInt32), output : Slice(UInt32)) : Nil
      return if input.empty?
      max_value = input.max
      mtf = StaticArray(UInt8, 256).new { |i| i.to_u8! }
      mtf_size = max_value.to_i32! &+ 1
      input.each_with_index do |value, i|
        index = 0
        while index < mtf_size && mtf[index] != value
          index &+= 1
        end
        output[i] = index.to_u32!
        moved = mtf[index]
        while index != 0
          mtf[index] = mtf[index &- 1]
          index &-= 1
        end
        mtf[0] = moved
      end
    end

    # Replaces zero runs of *v* with run-length prefix codes (extra bits
    # above bit 9); returns the new length and the largest prefix used.
    private def self.run_length_code_zeros(v : Slice(UInt32), max_run_length_prefix : UInt32) : {Int32, UInt32}
      in_size = v.size
      max_reps = 0_u32
      i = 0
      while i < in_size
        reps = 0_u32
        while i < in_size && v[i] != 0
          i &+= 1
        end
        while i < in_size && v[i] == 0
          reps &+= 1
          i &+= 1
        end
        max_reps = reps if reps > max_reps
      end
      max_prefix = max_reps > 0 ? Encode.log2_floor(max_reps) : 0_u32
      max_prefix = Math.min(max_prefix, max_run_length_prefix)
      out_size = 0
      i = 0
      while i < in_size
        if v[i] != 0
          v[out_size] = v[i] &+ max_prefix
          i &+= 1
          out_size &+= 1
        else
          reps = 1_u32
          k = i &+ 1
          while k < in_size && v[k] == 0
            reps &+= 1
            k &+= 1
          end
          i &+= reps
          while reps != 0
            if reps < (2_u32 << max_prefix)
              prefix = Encode.log2_floor(reps)
              v[out_size] = prefix &+ ((reps &- (1_u32 << prefix)) << 9)
              out_size &+= 1
              break
            else
              v[out_size] = max_prefix &+ (((1_u32 << max_prefix) &- 1) << 9)
              reps &-= (2_u32 << max_prefix) &- 1
              out_size &+= 1
            end
          end
        end
      end
      {out_size, max_prefix}
    end

    # google/brotli's EncodeContextMap.
    def self.encode_context_map(context_map : Slice(UInt32), num_clusters : Int32, tree : HuffmanNode*, arena : Arena,
                                writer : BitWriter) : Nil
      store_var_len_uint8(num_clusters &- 1, writer)
      return if num_clusters == 1
      symbols = Slice.new(arena.alloc_cleared(UInt32, context_map.size), context_map.size)
      move_to_front_transform(context_map, symbols)
      count, max_prefix = run_length_code_zeros(symbols, 6_u32)
      histogram = StaticArray(UInt32, 272).new(0_u32)
      depths = StaticArray(UInt8, 272).new(0_u8)
      bits = StaticArray(UInt16, 272).new(0_u16)
      count.times { |i| histogram[symbols[i] & 0x1FF] &+= 1 }
      use_rle = max_prefix > 0
      writer.write(1, use_rle ? 1 : 0)
      writer.write(4, max_prefix &- 1) if use_rle
      alphabet = num_clusters &+ max_prefix.to_i32!
      Entropy.build_and_store(histogram.to_unsafe, alphabet, alphabet, tree, depths.to_unsafe, bits.to_unsafe, writer)
      count.times do |i|
        symbol = symbols[i] & 0x1FF
        extra = symbols[i] >> 9
        writer.write(depths[symbol], bits[symbol])
        writer.write(symbol, extra) if symbol > 0 && symbol <= max_prefix
      end
      writer.write(1, 1)
    end

    # A context map where every context of a block type maps to the
    # type's own histogram (google/brotli's StoreTrivialContextMap).
    def self.store_trivial_context_map(num_types : Int32, context_bits : Int32, tree : HuffmanNode*,
                                       writer : BitWriter) : Nil
      store_var_len_uint8(num_types &- 1, writer)
      return unless num_types > 1
      repeat_code = context_bits &- 1
      repeat_bits = (1 << repeat_code) &- 1
      alphabet_size = num_types &+ repeat_code
      histogram = StaticArray(UInt32, 272).new(0_u32)
      depths = StaticArray(UInt8, 272).new(0_u8)
      bits = StaticArray(UInt16, 272).new(0_u16)
      writer.write(1, 1)
      writer.write(4, repeat_code &- 1)
      histogram[repeat_code] = num_types.to_u32!
      histogram[0] = 1_u32
      (context_bits...alphabet_size).each { |i| histogram[i] = 1_u32 }
      Entropy.build_and_store(histogram.to_unsafe, alphabet_size, alphabet_size, tree, depths.to_unsafe, bits.to_unsafe, writer)
      num_types.times do |i|
        code = i == 0 ? 0 : i &+ context_bits &- 1
        writer.write(depths[code], bits[code])
        writer.write(depths[repeat_code], bits[repeat_code])
        writer.write(repeat_code, repeat_bits)
      end
      writer.write(1, 1)
    end

    # google/brotli's BrotliStoreMetaBlock.
    def self.store(data : UInt8*, start : Int32, length : Int32, previous_byte : UInt8, previous_byte2 : UInt8,
                   is_last : Bool, params : DistanceParams, literal_context_mode : Int32,
                   commands : CommandBuffer, metablock : MetaBlock, arena : Arena, writer : BitWriter) : Nil
      writer.reserve(2 &* length &+ 503)
      store_compressed_header(is_last, length, writer)
      tree = arena.alloc(HuffmanNode, Entropy::MAX_TREE_SIZE)
      literal_encoder = BlockEncoder.new(NUM_LITERAL_SYMBOLS, metablock.literal_split, arena)
      command_encoder = BlockEncoder.new(NUM_COMMAND_SYMBOLS, metablock.command_split, arena)
      distance_encoder = BlockEncoder.new(params.alphabet_size.to_i32!, metablock.distance_split, arena)
      literal_encoder.store_block_switch_codes(tree, writer)
      command_encoder.store_block_switch_codes(tree, writer)
      distance_encoder.store_block_switch_codes(tree, writer)
      writer.write(2, params.postfix_bits)
      writer.write(4, params.direct_codes >> params.postfix_bits)
      metablock.literal_split.num_types.times { writer.write(2, literal_context_mode) }
      literal_map = metablock.literal_context_map
      distance_map = metablock.distance_context_map
      if literal_map.empty?
        store_trivial_context_map(metablock.literal_histograms.count, LITERAL_CONTEXT_BITS, tree, writer)
      else
        encode_context_map(literal_map, metablock.literal_histograms.count, tree, arena, writer)
      end
      if distance_map.empty?
        store_trivial_context_map(metablock.distance_histograms.count, DISTANCE_CONTEXT_BITS, tree, writer)
      else
        encode_context_map(distance_map, metablock.distance_histograms.count, tree, arena, writer)
      end
      literal_encoder.store_entropy_codes(metablock.literal_histograms, NUM_LITERAL_SYMBOLS, tree, writer)
      command_encoder.store_entropy_codes(metablock.command_histograms, NUM_COMMAND_SYMBOLS, tree, writer)
      distance_encoder.store_entropy_codes(metablock.distance_histograms, params.alphabet_size.to_i32!, tree, writer)
      lut = Tables::CONTEXT_LOOKUP.to_unsafe + literal_context_mode &* 512
      position = start
      literal_map_pointer = literal_map.to_unsafe
      distance_map_pointer = distance_map.to_unsafe
      commands.size.times do |i|
        entry = commands[i]
        command_encoder.store_symbol(entry.command_prefix, writer)
        store_command_extra(entry, writer)
        if literal_map.empty?
          entry.insert_length.times do
            literal_encoder.store_symbol(data[position], writer)
            position &+= 1
          end
        else
          entry.insert_length.times do
            literal = data[position]
            context = lut[previous_byte] | lut[256 &+ previous_byte2]
            literal_encoder.store_symbol_with_context(literal, context, literal_map_pointer, LITERAL_CONTEXT_BITS, writer)
            previous_byte2 = previous_byte
            previous_byte = literal
            position &+= 1
          end
        end
        copy = entry.copy_length.to_i32!
        position &+= copy
        if copy != 0
          previous_byte2 = data[position &- 2]
          previous_byte = data[position &- 1]
          if entry.command_prefix >= 128
            code = entry.distance_prefix & 0x3FF
            if distance_map.empty?
              distance_encoder.store_symbol(code, writer)
            else
              distance_encoder.store_symbol_with_context(code, entry.distance_context, distance_map_pointer,
                DISTANCE_CONTEXT_BITS, writer)
            end
            writer.write(entry.distance_prefix >> 10, entry.distance_extra)
          end
        end
      end
      writer.align if is_last
    end

    @[AlwaysInline]
    private def self.store_command_extra(entry : Command, writer : BitWriter) : Nil
      copy_code_length = entry.copy_length_code
      insert_code = Encode.insert_length_code(entry.insert_length)
      copy_code = Encode.copy_length_code(copy_code_length)
      insert_extra_count = INSERT_EXTRA.unsafe_fetch(insert_code)
      insert_extra = (entry.insert_length &- INSERT_BASE.unsafe_fetch(insert_code)).to_u64!
      copy_extra = (copy_code_length &- COPY_BASE.unsafe_fetch(copy_code)).to_u64!
      writer.write(insert_extra_count &+ COPY_EXTRA.unsafe_fetch(copy_code), (copy_extra << insert_extra_count) | insert_extra)
    end
  end
end
