module Amber::Mica::Deflate
  # Builds the Huffman code of one alphabet for the encoder: optimal code
  # lengths from symbol frequencies, limited to `max_bits`, and the
  # canonical codes RFC 1951 section 3.2.2 assigns to those lengths, stored
  # bit-reversed (the order DEFLATE sends them in).
  #
  # The construction is zlib's (`build_tree`, `gen_bitlen` and `gen_codes`
  # of trees.c): a heap ordered by frequency and then by subtree depth, and,
  # when a code would pass `max_bits`, the same redistribution of the
  # overflowing leaves. Following it step for step gives the lengths zlib
  # gives for the same frequencies, so compressed sizes track zlib's.
  #
  # One builder serves every block of a stream: `reset` clears the
  # frequencies and `build` reuses the arrays.
  #
  # :nodoc:
  class HuffmanCodeBuilder
    # Symbols in the alphabet.
    getter symbol_count : Int32
    # The largest symbol with a nonzero frequency after `build`.
    getter max_code : Int32 = -1
    # Bits the block's symbols take with this code (code bits plus extra
    # bits, times each frequency), set by `build`.
    getter optimal_bits : Int32 = 0
    # The same total under the fixed code whose lengths were given.
    getter static_bits : Int32 = 0

    @frequency : Int32*
    @parent : Int32*
    @heap : Int32*
    @code : UInt16*
    @length : UInt8*
    # A node's place in the order the tree is built in: its frequency
    # above bit 8 and the depth of its subtree in the low 8 bits.
    @key : UInt64*
    @max_bits : Int32
    @extra_bits : Slice(UInt8)?
    @extra_base : Int32
    @static_length : Slice(UInt8)?

    # Bytes of storage a builder for *symbol_count* symbols works in: a
    # tree has up to 2n + 1 nodes (n leaves, n - 1 joins and slot 0 of the
    # heap). The count is a multiple of 8, so builders can share one block.
    def self.storage_bytes(symbol_count : Int32) : Int32
      nodes = 2 * symbol_count + 1
      (nodes * 17 + symbol_count * 6 + 7) & ~7
    end

    # *extra_bits* holds the extra bits of symbol `extra_base + index`;
    # *static_length* the fixed code's lengths, for alphabets that have one.
    # *storage* is `storage_bytes` of zeroed memory aligned to 8 bytes that
    # outlives the builder; without it the collector supplies the memory.
    def initialize(@symbol_count : Int32, @max_bits : Int32, @extra_bits : Slice(UInt8)? = nil, @extra_base : Int32 = 0,
                   @static_length : Slice(UInt8)? = nil, storage : UInt8* = Pointer(UInt8).null)
      # One block holds the six arrays, widest elements first.
      nodes = 2 * @symbol_count + 1
      storage = Pointer(UInt8).malloc(HuffmanCodeBuilder.storage_bytes(@symbol_count)) if storage.null?
      @key = storage.as(UInt64*)
      @parent = (storage + nodes * 8).as(Int32*)
      @heap = (storage + nodes * 12).as(Int32*)
      @frequency = (storage + nodes * 16).as(Int32*)
      @code = (storage + nodes * 16 + @symbol_count * 4).as(UInt16*)
      @length = storage + nodes * 16 + @symbol_count * 6
    end

    # The frequency counters, one per symbol; the encoder's loops add to
    # them through this pointer.
    def frequencies : Int32*
      @frequency
    end

    # The code length of each symbol after `build` (0 for unused symbols).
    def lengths : UInt8*
      @length
    end

    # The bit-reversed code of each symbol after `build`.
    def codes : UInt16*
      @code
    end

    # Clears every frequency for the next block.
    def reset : Nil
      @frequency.clear(@symbol_count)
    end

    # Computes lengths and codes from the current frequencies.
    def build : Nil
      frequency = @frequency
      length = @length
      parent = @parent
      heap = @heap
      key = @key
      static_length = @static_length
      heap_size = 2 * @symbol_count + 1
      heap_length = 0
      heap_max = heap_size
      max_code = -1
      optimal_bits = 0
      static_bits = 0

      symbol = 0
      while symbol < @symbol_count
        if frequency[symbol] != 0
          heap_length += 1
          heap[heap_length] = symbol
          max_code = symbol
          key[symbol] = frequency[symbol].to_u64! << 8
        else
          length[symbol] = 0_u8
        end
        symbol += 1
      end

      # DEFLATE needs at least one distance code and a decoder (zlib's
      # included) wants a complete code, so a code with fewer than two
      # symbols gains symbols of frequency 1. Their cost is taken back out
      # of the totals.
      while heap_length < 2
        forced = max_code < 2 ? (max_code += 1) : 0
        heap_length += 1
        heap[heap_length] = forced
        frequency[forced] = 1
        key[forced] = 1_u64 << 8
        optimal_bits -= 1
        static_bits -= static_length[forced].to_i32 if static_length
      end
      @max_code = max_code

      index = heap_length // 2
      while index >= 1
        sift_down(heap, key, heap_length, index)
        index -= 1
      end

      # Join the two least frequent nodes until one tree is left.
      node = @symbol_count
      loop do
        least = heap[1]
        heap[1] = heap[heap_length]
        heap_length &-= 1
        sift_down(heap, key, heap_length, 1)
        next_least = heap[1]

        heap_max &-= 1
        heap[heap_max] = least
        heap_max &-= 1
        heap[heap_max] = next_least

        least_key = key[least]
        next_least_key = key[next_least]
        depth = (Math.max(least_key & 0xFF, next_least_key & 0xFF) &+ 1) & 0xFF
        key[node] = (((least_key >> 8) &+ (next_least_key >> 8)) << 8) | depth
        parent[least] = node
        parent[next_least] = node
        heap[1] = node
        node &+= 1
        sift_down(heap, key, heap_length, 1)
        break if heap_length < 2
      end
      heap_max -= 1
      heap[heap_max] = heap[1]

      optimal_bits, static_bits = assign_lengths(heap_max, heap_size, max_code, optimal_bits, static_bits)
      @optimal_bits = optimal_bits
      @static_bits = static_bits
      assign_codes(max_code)
    end

    # Restores the heap property below *start* (zlib's `pqdownheap`): the
    # node with the smaller frequency rises, and of two equal frequencies
    # the shallower subtree, which is the order of the keys.
    @[AlwaysInline]
    private def sift_down(heap : Int32*, key : UInt64*, heap_length : Int32, start : Int32) : Nil
      value = heap[start]
      value_key = key[value]
      position = start
      child = position << 1
      while child <= heap_length
        child_key = key[heap[child]]
        if child < heap_length
          sibling_key = key[heap[child &+ 1]]
          if sibling_key <= child_key
            child &+= 1
            child_key = sibling_key
          end
        end
        break if value_key <= child_key
        heap[position] = heap[child]
        position = child
        child <<= 1
      end
      heap[position] = value
    end

    # Turns the tree into code lengths (zlib's `gen_bitlen`): each node is
    # one bit longer than its parent; lengths past `max_bits` are cut to it
    # and the code is rebalanced by moving leaves down.
    private def assign_lengths(heap_max : Int32, heap_size : Int32, max_code : Int32, optimal_bits : Int32,
                               static_bits : Int32) : {Int32, Int32}
      frequency = @frequency
      length = @length
      parent = @parent
      heap = @heap
      extra_bits = @extra_bits
      static_length = @static_length
      max_bits = @max_bits
      count_of_length = uninitialized StaticArray(Int32, 16)
      count_of_length.fill(0)
      overflow = 0

      length[heap[heap_max]] = 0_u8
      position = heap_max + 1
      while position < heap_size
        node = heap[position]
        position += 1
        bits = length[parent[node]].to_i32 + 1
        if bits > max_bits
          bits = max_bits
          overflow += 1
        end
        length[node] = bits.to_u8!
        next if node > max_code
        count_of_length[bits] += 1
        extra = 0
        if extra_bits && node >= @extra_base
          extra = extra_bits[node - @extra_base].to_i32
        end
        optimal_bits += frequency[node] * (bits + extra)
        static_bits += frequency[node] * (static_length[node].to_i32 + extra) if static_length
      end
      return {optimal_bits, static_bits} if overflow == 0

      loop do
        bits = max_bits - 1
        while count_of_length[bits] == 0
          bits -= 1
        end
        count_of_length[bits] -= 1
        count_of_length[bits + 1] += 2
        count_of_length[max_bits] -= 1
        overflow -= 2
        break if overflow <= 0
      end

      # Hand the lengths out again, longest first, to the least frequent
      # leaves first.
      position = heap_size
      bits = max_bits
      while bits != 0
        remaining = count_of_length[bits]
        while remaining != 0
          position -= 1
          node = heap[position]
          next if node > max_code
          if length[node].to_i32 != bits
            optimal_bits += (bits - length[node].to_i32) * frequency[node]
            length[node] = bits.to_u8!
          end
          remaining -= 1
        end
        bits -= 1
      end
      {optimal_bits, static_bits}
    end

    # Assigns canonical codes to the lengths (zlib's `gen_codes`).
    private def assign_codes(max_code : Int32) : Nil
      HuffmanCodeBuilder.assign_canonical_codes(@length, @code, max_code + 1)
    end

    # Writes into *code* the bit-reversed canonical code of each of the
    # first *count* symbols of *length*.
    def self.assign_canonical_codes(length : UInt8*, code : UInt16*, count : Int32) : Nil
      count_of_length = uninitialized StaticArray(Int32, 16)
      count_of_length.fill(0)
      symbol = 0
      while symbol < count
        count_of_length[length[symbol]] += 1
        symbol += 1
      end
      # Unused symbols (length 0) take no code.
      count_of_length[0] = 0
      next_code = uninitialized StaticArray(UInt32, 16)
      value = 0_u32
      bits = 1
      while bits <= 15
        value = (value &+ count_of_length[bits - 1].to_u32!) << 1
        next_code[bits] = value
        bits += 1
      end
      symbol = 0
      while symbol < count
        bits = length[symbol].to_i32
        if bits != 0
          code[symbol] = reverse_bits(next_code[bits], bits)
          next_code[bits] &+= 1
        end
        symbol += 1
      end
    end

    # Returns the low *count* bits of *value* in reverse order.
    @[AlwaysInline]
    def self.reverse_bits(value : UInt32, count : Int32) : UInt16
      (value.bit_reverse >> (32 - count)).to_u16!
    end
  end
end
