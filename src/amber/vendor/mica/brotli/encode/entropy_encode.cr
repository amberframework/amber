module Amber::Mica::Brotli::Encode
  # A node of the Huffman tree builder: a leaf holds its symbol in
  # *right_or_value* and -1 in *left*.
  struct HuffmanNode
    property total_count : UInt32
    property left : Int16
    property right_or_value : Int16

    def initialize(@total_count, @left, @right_or_value)
    end
  end

  # Prefix code construction and storage (google/brotli's
  # entropy_encode.c and the tree parts of brotli_bit_stream.c).
  module Entropy
    SHELL_GAPS    = StaticArray[132, 57, 23, 10, 4, 1]
    MAX_TREE_SIZE = 2 &* NUM_COMMAND_SYMBOLS &+ 1

    # The order code length code lengths are stored in, and the fixed code
    # for code length code lengths 0 to 5 (RFC 7932, section 3.5).
    STORAGE_ORDER       = StaticArray[1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
    LENGTH_CODE_SYMBOLS = StaticArray[0, 7, 3, 2, 1, 15]
    LENGTH_CODE_BITS    = StaticArray[2, 4, 3, 2, 2, 4]

    @[AlwaysInline]
    private def self.sorts_before?(a : HuffmanNode, b : HuffmanNode) : Bool
      a.total_count != b.total_count ? a.total_count < b.total_count : a.right_or_value > b.right_or_value
    end

    private def self.sort_nodes(items : HuffmanNode*, n : Int32) : Nil
      if n < 13
        (1...n).each do |i|
          tmp = items[i]
          k = i
          j = i &- 1
          while sorts_before?(tmp, items[j])
            items[k] = items[j]
            k = j
            break if j == 0
            j &-= 1
          end
          items[k] = tmp
        end
      else
        (n < 57 ? 2 : 0).upto(5) do |g|
          gap = SHELL_GAPS[g]
          (gap...n).each do |i|
            j = i
            tmp = items[i]
            while j >= gap && sorts_before?(tmp, items[j &- gap])
              items[j] = items[j &- gap]
              j &-= gap
            end
            items[j] = tmp
          end
        end
      end
    end

    private def self.set_depth(root : Int32, pool : HuffmanNode*, depth : UInt8*, max_depth : Int32) : Bool
      stack = StaticArray(Int32, 16).new(0)
      level = 0
      p = root
      stack[0] = -1
      loop do
        if pool[p].left >= 0
          level &+= 1
          return false if level > max_depth
          stack[level] = pool[p].right_or_value.to_i32!
          p = pool[p].left.to_i32!
          next
        else
          depth[pool[p].right_or_value] = level.to_u8!
        end
        while level >= 0 && stack[level] == -1
          level &-= 1
        end
        return true if level < 0
        p = stack[level]
        stack[level] = -1
      end
    end

    # Code lengths of at most *tree_limit* bits for `data[0, length]`
    # (google/brotli's BrotliCreateHuffmanTree): counts below a floor are
    # raised to it, doubling the floor until the tree fits.
    def self.create_huffman_tree(data : UInt32*, length : Int32, tree_limit : Int32, tree : HuffmanNode*, depth : UInt8*) : Nil
      sentinel = HuffmanNode.new(UInt32::MAX, -1_i16, -1_i16)
      count_limit = 1_u32
      loop do
        n = 0
        i = length
        while i != 0
          i &-= 1
          if data[i] != 0
            tree[n] = HuffmanNode.new(Math.max(data[i], count_limit), -1_i16, i.to_i16)
            n &+= 1
          end
        end
        if n == 1
          depth[tree[0].right_or_value] = 1_u8
          break
        end
        sort_nodes(tree, n)
        tree[n] = sentinel
        tree[n &+ 1] = sentinel
        i = 0
        j = n &+ 1
        k = n &- 1
        while k != 0
          if tree[i].total_count <= tree[j].total_count
            left = i
            i &+= 1
          else
            left = j
            j &+= 1
          end
          if tree[i].total_count <= tree[j].total_count
            right = i
            i &+= 1
          else
            right = j
            j &+= 1
          end
          j_end = 2 &* n &- k
          tree[j_end] = HuffmanNode.new(tree[left].total_count &+ tree[right].total_count, left.to_i16, right.to_i16)
          tree[j_end &+ 1] = sentinel
          k &-= 1
        end
        break if set_depth(2 &* n &- 1, tree, depth, tree_limit)
        count_limit &*= 2
      end
    end

    # Smooths `counts[0, length]` so the code lengths run-length code
    # better (google/brotli's BrotliOptimizeHuffmanCountsForRle).
    def self.optimize_for_rle(length : Int32, counts : UInt32*, good_for_rle : UInt8*) : Nil
      streak_limit = 1240_u64
      nonzero_count = 0
      length.times { |i| nonzero_count &+= 1 if counts[i] != 0 }
      return if nonzero_count < 16
      while length != 0 && counts[length &- 1] == 0
        length &-= 1
      end
      return if length == 0
      nonzeros = 0
      smallest_nonzero = 1_u32 << 30
      length.times do |i|
        if counts[i] != 0
          nonzeros &+= 1
          smallest_nonzero = counts[i] if smallest_nonzero > counts[i]
        end
      end
      return if nonzeros < 5
      if smallest_nonzero < 4
        zeros = length &- nonzeros
        if zeros < 6
          (1...(length &- 1)).each do |i|
            counts[i] = 1_u32 if counts[i &- 1] != 0 && counts[i] == 0 && counts[i &+ 1] != 0
          end
        end
      end
      return if nonzeros < 28
      Slice.new(good_for_rle, length).fill(0_u8)
      symbol = counts[0]
      step = 0
      (0..length).each do |i|
        if i == length || counts[i] != symbol
          if (symbol == 0 && step >= 5) || (symbol != 0 && step >= 7)
            step.times { |k| good_for_rle[i &- k &- 1] = 1_u8 }
          end
          step = 1
          symbol = counts[i] if i != length
        else
          step &+= 1
        end
      end
      stride = 0
      limit = 256_u64 &* (counts[0].to_u64! &+ counts[1] &+ counts[2]) // 3 &+ 420
      sum = 0_u64
      (0..length).each do |i|
        if i == length || good_for_rle[i] != 0 || (i != 0 && good_for_rle[i &- 1] != 0) ||
           (256_u64 &* counts[i] &- limit &+ streak_limit) >= 2 &* streak_limit
          if stride >= 4 || (stride >= 3 && sum == 0)
            count = (sum &+ (stride // 2).to_u64!) // stride.to_u64!
            count = 1_u64 if count == 0
            count = 0_u64 if sum == 0
            stride.times { |k| counts[i &- k &- 1] = count.to_u32! }
          end
          stride = 0
          sum = 0_u64
          if i < length &- 2
            limit = 256_u64 &* (counts[i].to_u64! &+ counts[i &+ 1] &+ counts[i &+ 2]) // 3 &+ 420
          elsif i < length
            limit = 256_u64 &* counts[i]
          else
            limit = 0_u64
          end
        end
        stride &+= 1
        if i != length
          sum &+= counts[i]
          limit = (256_u64 &* sum &+ (stride // 2).to_u64!) // stride.to_u64! if stride >= 4
          limit &+= 120 if stride == 4
        end
      end
    end

    private def self.write_repetitions(previous : UInt8, value : UInt8, repetitions : Int32,
                                       tree : UInt8*, extra : UInt8*, size : Int32) : Int32
      if previous != value
        tree[size] = value
        extra[size] = 0_u8
        size &+= 1
        repetitions &-= 1
      end
      if repetitions == 7
        tree[size] = value
        extra[size] = 0_u8
        size &+= 1
        repetitions &-= 1
      end
      if repetitions < 3
        repetitions.times do
          tree[size] = value
          extra[size] = 0_u8
          size &+= 1
        end
      else
        start = size
        repetitions &-= 3
        loop do
          tree[size] = REPEAT_PREVIOUS_LENGTH.to_u8!
          extra[size] = (repetitions & 3).to_u8!
          size &+= 1
          repetitions >>= 2
          break if repetitions == 0
          repetitions &-= 1
        end
        reverse(tree, start, size)
        reverse(extra, start, size)
      end
      size
    end

    private def self.write_zero_repetitions(repetitions : Int32, tree : UInt8*, extra : UInt8*, size : Int32) : Int32
      if repetitions == 11
        tree[size] = 0_u8
        extra[size] = 0_u8
        size &+= 1
        repetitions &-= 1
      end
      if repetitions < 3
        repetitions.times do
          tree[size] = 0_u8
          extra[size] = 0_u8
          size &+= 1
        end
      else
        start = size
        repetitions &-= 3
        loop do
          tree[size] = REPEAT_ZERO_LENGTH.to_u8!
          extra[size] = (repetitions & 7).to_u8!
          size &+= 1
          repetitions >>= 3
          break if repetitions == 0
          repetitions &-= 1
        end
        reverse(tree, start, size)
        reverse(extra, start, size)
      end
      size
    end

    private def self.reverse(values : UInt8*, start : Int32, stop : Int32) : Nil
      stop &-= 1
      while start < stop
        values[start], values[stop] = values[stop], values[start]
        start &+= 1
        stop &-= 1
      end
    end

    # The code length symbols (with repeat codes 16 and 17) for
    # `depth[0, length]`; returns how many (google/brotli's
    # BrotliWriteHuffmanTree).
    def self.write_huffman_tree(depth : UInt8*, length : Int32, tree : UInt8*, extra : UInt8*) : Int32
      previous = INITIAL_REPEATED_LENGTH.to_u8!
      new_length = length
      length.times do |i|
        break unless depth[length &- i &- 1] == 0
        new_length &-= 1
      end
      use_rle_for_non_zero = false
      use_rle_for_zero = false
      if length > 50
        total_reps_zero = 0
        total_reps_non_zero = 0
        count_reps_zero = 1
        count_reps_non_zero = 1
        i = 0
        while i < new_length
          value = depth[i]
          reps = 1
          while i &+ reps < new_length && depth[i &+ reps] == value
            reps &+= 1
          end
          if reps >= 3 && value == 0
            total_reps_zero &+= reps
            count_reps_zero &+= 1
          end
          if reps >= 4 && value != 0
            total_reps_non_zero &+= reps
            count_reps_non_zero &+= 1
          end
          i &+= reps
        end
        use_rle_for_non_zero = total_reps_non_zero > count_reps_non_zero &* 2
        use_rle_for_zero = total_reps_zero > count_reps_zero &* 2
      end
      size = 0
      i = 0
      while i < new_length
        value = depth[i]
        reps = 1
        if (value != 0 && use_rle_for_non_zero) || (value == 0 && use_rle_for_zero)
          while i &+ reps < new_length && depth[i &+ reps] == value
            reps &+= 1
          end
        end
        if value == 0
          size = write_zero_repetitions(reps, tree, extra, size)
        else
          size = write_repetitions(previous, value, reps, tree, extra, size)
          previous = value
        end
        i &+= reps
      end
      size
    end

    # The low *num_bits* (1 to 16) of *bits* in reverse order.
    @[AlwaysInline]
    private def self.reverse_bits(num_bits : Int32, bits : UInt16) : UInt16
      bits.to_u32!.bit_reverse.unsafe_shr(32 &- num_bits).to_u16!
    end

    # Canonical codes for `depth[0, length]`, bit-reversed for writing.
    def self.convert_bit_depths_to_symbols(depth : UInt8*, length : Int32, bits : UInt16*) : Nil
      bl_count = StaticArray(UInt16, 16).new(0_u16)
      next_code = StaticArray(UInt16, 16).new(0_u16)
      length.times { |i| bl_count[depth[i]] &+= 1 }
      bl_count[0] = 0_u16
      code = 0
      (1...16).each do |i|
        code = (code &+ bl_count[i &- 1]) << 1
        next_code[i] = code.to_u16!
      end
      length.times do |i|
        d = depth[i]
        next if d == 0
        bits[i] = reverse_bits(d.to_i32!, next_code[d])
        next_code[d] &+= 1
      end
    end

    private def self.store_huffman_tree_of_huffman_tree(num_codes : Int32, code_length_depth : UInt8*, writer : BitWriter) : Nil
      skip_some = 0
      codes_to_store = CODE_LENGTH_CODES
      if num_codes > 1
        while codes_to_store > 0
          break if code_length_depth[STORAGE_ORDER[codes_to_store &- 1]] != 0
          codes_to_store &-= 1
        end
      end
      if code_length_depth[STORAGE_ORDER[0]] == 0 && code_length_depth[STORAGE_ORDER[1]] == 0
        skip_some = 2
        skip_some = 3 if code_length_depth[STORAGE_ORDER[2]] == 0
      end
      writer.write(2, skip_some)
      (skip_some...codes_to_store).each do |i|
        l = code_length_depth[STORAGE_ORDER[i]]
        writer.write(LENGTH_CODE_BITS[l], LENGTH_CODE_SYMBOLS[l])
      end
    end

    # Stores a complex prefix code given its code lengths
    # (google/brotli's BrotliStoreHuffmanTree).
    def self.store_huffman_tree(depth : UInt8*, num : Int32, tree : HuffmanNode*, writer : BitWriter) : Nil
      huffman_tree = StaticArray(UInt8, 704).new(0_u8)
      extra_bits = StaticArray(UInt8, 704).new(0_u8)
      code_length_depth = StaticArray(UInt8, 18).new(0_u8)
      code_length_symbols = StaticArray(UInt16, 18).new(0_u16)
      histogram = StaticArray(UInt32, 18).new(0_u32)
      size = write_huffman_tree(depth, num, huffman_tree.to_unsafe, extra_bits.to_unsafe)
      size.times { |i| histogram[huffman_tree[i]] &+= 1 }
      num_codes = 0
      code = 0
      CODE_LENGTH_CODES.times do |i|
        next if histogram[i] == 0
        if num_codes == 0
          code = i
          num_codes = 1
        elsif num_codes == 1
          num_codes = 2
          break
        end
      end
      create_huffman_tree(histogram.to_unsafe, CODE_LENGTH_CODES, 5, tree, code_length_depth.to_unsafe)
      convert_bit_depths_to_symbols(code_length_depth.to_unsafe, CODE_LENGTH_CODES, code_length_symbols.to_unsafe)
      store_huffman_tree_of_huffman_tree(num_codes, code_length_depth.to_unsafe, writer)
      code_length_depth[code] = 0_u8 if num_codes == 1
      size.times do |i|
        symbol = huffman_tree[i]
        writer.write(code_length_depth[symbol], code_length_symbols[symbol])
        if symbol == REPEAT_PREVIOUS_LENGTH
          writer.write(2, extra_bits[i])
        elsif symbol == REPEAT_ZERO_LENGTH
          writer.write(3, extra_bits[i])
        end
      end
    end

    private def self.store_simple_huffman_tree(depth : UInt8*, symbols : StaticArray(Int32, 4), num_symbols : Int32,
                                               max_bits : Int32, writer : BitWriter) : Nil
      writer.write(2, 1)
      writer.write(2, num_symbols &- 1)
      num_symbols.times do |i|
        (i &+ 1...num_symbols).each do |j|
          symbols[j], symbols[i] = symbols[i], symbols[j] if depth[symbols[j]] < depth[symbols[i]]
        end
      end
      num_symbols.times { |i| writer.write(max_bits, symbols[i]) }
      writer.write(1, depth[symbols[0]] == 1 ? 1 : 0) if num_symbols == 4
    end

    # Builds the prefix code for `histogram[0, length]` into *depth* and
    # *bits* and stores it (google/brotli's BuildAndStoreHuffmanTree).
    def self.build_and_store(histogram : UInt32*, length : Int32, alphabet_size : Int32, tree : HuffmanNode*,
                             depth : UInt8*, bits : UInt16*, writer : BitWriter) : Nil
      count = 0
      s4 = StaticArray(Int32, 4).new(0)
      length.times do |i|
        next if histogram[i] == 0
        if count < 4
          s4[count] = i
        elsif count > 4
          break
        end
        count &+= 1
      end
      max_bits = 0
      counter = alphabet_size &- 1
      while counter != 0
        counter >>= 1
        max_bits &+= 1
      end
      if count <= 1
        writer.write(4, 1)
        writer.write(max_bits, s4[0])
        depth[s4[0]] = 0_u8
        bits[s4[0]] = 0_u16
        return
      end
      Slice.new(depth, length).fill(0_u8)
      create_huffman_tree(histogram, length, 15, tree, depth)
      convert_bit_depths_to_symbols(depth, length, bits)
      if count <= 4
        store_simple_huffman_tree(depth, s4, count, max_bits, writer)
      else
        store_huffman_tree(depth, length, tree, writer)
      end
    end
  end
end
