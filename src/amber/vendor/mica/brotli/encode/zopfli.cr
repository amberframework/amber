module Amber::Mica::Brotli::Encode
  # A match for the optimal parse: distance, and length << 5 with the
  # length code in the low 5 bits when a dictionary word is cut or
  # transformed (google/brotli's BackwardMatch).
  record BackwardMatch, distance : UInt32, length_and_code : UInt32 do
    @[AlwaysInline]
    def length : Int32
      (length_and_code >> 5).to_i32
    end

    @[AlwaysInline]
    def length_code : Int32
      code = (length_and_code & 31).to_i32
      code != 0 ? code : length
    end
  end

  # google/brotli's H10: per hash bucket, a binary tree of the positions
  # whose first 128 bytes sort in order, re-rooted at every new position,
  # so one walk finds every longer match (qualities 10 and 11).
  class BinaryTreeHasher
    BUCKET_BITS           =  17
    MAX_TREE_SEARCH_DEPTH =  64
    MAX_TREE_COMP_LENGTH  = 128
    MAX_NUM_MATCHES       = 128

    @buckets : Pointer(UInt32)
    @forest : Pointer(UInt32)
    @window_mask : UInt32
    @invalid_position : UInt32

    def initialize(window_bits : Int32, one_shot : Bool, input_size : Int32)
      num_nodes = 1 << window_bits
      num_nodes = input_size if one_shot && input_size < num_nodes
      @buckets = Encode.table(UInt32, 1 << BUCKET_BITS)
      @forest = Encode.table(UInt32, 2 * Math.max(num_nodes, 1))
      @window_mask = ((1_u32 << window_bits) - 1)
      @invalid_position = 0_u32 &- @window_mask
    end

    def hash_type_length : Int32
      4
    end

    def store_lookahead : Int32
      MAX_TREE_COMP_LENGTH
    end

    def release : Nil
      @buckets = Encode.free_table(@buckets)
      @forest = Encode.free_table(@forest)
    end

    def finalize
      release
    end

    def prepare : Nil
      Slice.new(@buckets, 1 << BUCKET_BITS).fill(@invalid_position)
    end

    @[AlwaysInline]
    private def hash_bytes(data : UInt8*) : UInt32
      (Encode.load32(data) &* HASH_MUL32) >> (32 - BUCKET_BITS)
    end

    @[AlwaysInline]
    private def left_child(position : UInt32) : UInt32
      2_u32 &* (position & @window_mask)
    end

    @[AlwaysInline]
    private def right_child(position : UInt32) : UInt32
      2_u32 &* (position & @window_mask) &+ 1
    end

    # Walks the bucket's tree for matches at *position* (when *matches* is
    # given) and re-roots the tree there when 128 bytes follow it.
    private def store_and_find_matches(data : UInt8*, position : Int32, max_length : Int32, max_backward : Int32,
                                       best_length : Int32, matches : Pointer(BackwardMatch), count : Int32) : {Int32, Int32}
      current = position.to_u32
      max_comp_length = Math.min(max_length, MAX_TREE_COMP_LENGTH)
      reroot = max_length >= MAX_TREE_COMP_LENGTH
      key = hash_bytes(data + position)
      previous = @buckets[key]
      node_left = left_child(current)
      node_right = right_child(current)
      best_length_left = 0
      best_length_right = 0
      @buckets[key] = current if reroot
      depth_remaining = MAX_TREE_SEARCH_DEPTH
      loop do
        backward = current &- previous
        if backward == 0 || backward > max_backward.to_u32 || depth_remaining == 0
          if reroot
            @forest[node_left] = @invalid_position
            @forest[node_right] = @invalid_position
          end
          break
        end
        previous_position = previous.to_i32
        current_length = Math.min(best_length_left, best_length_right)
        length = current_length + Encode.match_length(data + position + current_length,
          data + previous_position + current_length, max_length - current_length)
        if !matches.null? && length > best_length
          best_length = length
          matches[count] = BackwardMatch.new(backward, (length << 5).to_u32)
          count += 1
        end
        if length >= max_comp_length
          if reroot
            @forest[node_left] = @forest[left_child(previous)]
            @forest[node_right] = @forest[right_child(previous)]
          end
          break
        end
        if data[position + length] > data[previous_position + length]
          best_length_left = length
          @forest[node_left] = previous if reroot
          node_left = right_child(previous)
          previous = @forest[node_left]
        else
          best_length_right = length
          @forest[node_right] = previous if reroot
          node_right = left_child(previous)
          previous = @forest[node_right]
        end
        depth_remaining -= 1
      end
      {best_length, count}
    end

    # Every match at *position* longer than all closer ones, short ones
    # from the last 16 (64 at quality 11) bytes, tree ones, then static
    # dictionary words; returns how many were written to *matches*
    # (google/brotli's FindAllMatchesH10).
    def find_all_matches(data : UInt8*, position : Int32, max_length : Int32, max_backward : Int32,
                         dictionary_distance : Int32, max_distance : Int32, quality : Int32,
                         matches : Pointer(BackwardMatch)) : Int32
      count = 0
      best_length = 1
      short_match_max_backward = quality != 11 ? 16 : 64
      stop = position - short_match_max_backward
      stop = 0 if position < short_match_max_backward
      current = data + position
      i = position - 1
      while i > stop && best_length <= 2
        backward = position - i
        break if backward > max_backward
        previous = data + i
        if current[0] == previous[0] && current[1] == previous[1]
          length = Encode.match_length(previous, current, max_length)
          if length > best_length
            best_length = length
            matches[count] = BackwardMatch.new(backward.to_u32, (length << 5).to_u32)
            count += 1
          end
        end
        i -= 1
      end
      if best_length < max_length
        best_length, count = store_and_find_matches(data, position, max_length, max_backward, best_length, matches, count)
      end
      dictionary_matches = StaticArray(UInt32, 38).new(StaticDictionary::INVALID_MATCH)
      min_length = Math.max(4, best_length + 1)
      if StaticDictionary.find_all(current, min_length, max_length, dictionary_matches.to_unsafe)
        max_word_length = Math.min(StaticDictionary::MAX_MATCH_LENGTH, max_length)
        (min_length..max_word_length).each do |length|
          id = dictionary_matches[length]
          next unless id < StaticDictionary::INVALID_MATCH
          distance = dictionary_distance.to_i64 + (id >> 5) + 1
          if distance <= max_distance
            code = (id & 31).to_i32
            matches[count] = BackwardMatch.new(distance.to_u32, ((length << 5) | (length == code ? 0 : code)).to_u32)
            count += 1
          end
        end
      end
      count
    end

    def store(data : UInt8*, position : Int32) : Nil
      max_backward = (@window_mask - WINDOW_GAP + 1).to_i32
      store_and_find_matches(data, position, MAX_TREE_COMP_LENGTH, max_backward, 0, Pointer(BackwardMatch).null, 0)
    end

    def store_range(data : UInt8*, start : Int32, stop : Int32) : Nil
      i = start
      j = start
      i = stop - 63 if start + 63 <= stop
      if start + 512 <= i
        while j < i
          store(data, j)
          j += 8
        end
      end
      while i < stop
        store(data, i)
        i += 1
      end
    end

    def stitch_to_previous_block(num_bytes : Int32, position : Int32, data : UInt8*) : Nil
      return unless num_bytes >= hash_type_length - 1 && position >= MAX_TREE_COMP_LENGTH
      start = position - MAX_TREE_COMP_LENGTH + 1
      stop = Math.min(position, start + num_bytes)
      (start...stop).each do |i|
        max_backward = (@window_mask - Math.max(WINDOW_GAP - 1, position - i)).to_i32
        store_and_find_matches(data, i, MAX_TREE_COMP_LENGTH, max_backward, 0, Pointer(BackwardMatch).null, 0)
      end
    end
  end

  # The optimal parse of qualities 10 and 11 (google/brotli's
  # backward_references_hq.c): a shortest path over byte positions where
  # each edge is a command costed by a histogram model.
  module Zopfli
    INFINITY              = 1.7e38_f32
    MAX_ZOPFLI_LENGTH_10  =        150
    MAX_ZOPFLI_LENGTH_11  =        325
    LONG_COPY_QUICK_STEP  =      16384
    DISTANCE_CACHE_INDEX  = StaticArray[0, 1, 2, 3, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1]
    DISTANCE_CACHE_OFFSET = StaticArray[0, 0, 0, 0, -1, 1, -2, 2, -3, 3, -1, 1, -2, 2, -3, 3]

    # One position of the path: the best command reaching it. *length*
    # holds the copy length and, above bit 25, 9 + length - length code;
    # *dcode_insert_length* the insert length and, above bit 27, the short
    # distance code + 1; *cost* doubles as the shortcut and next fields.
    struct Node
      property length : UInt32 = 1_u32
      property distance : UInt32 = 0_u32
      property dcode_insert_length : UInt32 = 0_u32
      property cost : Float32 = INFINITY
      property link : UInt32 = 0_u32

      def initialize
      end

      @[AlwaysInline]
      def copy_length : UInt32
        @length & 0x1FFFFFF
      end

      @[AlwaysInline]
      def length_code : UInt32
        copy_length &+ 9 &- (@length >> 25)
      end

      @[AlwaysInline]
      def distance_code : UInt32
        short_code = @dcode_insert_length >> 27
        short_code == 0 ? @distance &+ NUM_DISTANCE_SHORT_CODES &- 1 : short_code &- 1
      end

      @[AlwaysInline]
      def insert_length : UInt32
        @dcode_insert_length & 0x7FFFFFF
      end

      @[AlwaysInline]
      def command_length : UInt32
        copy_length &+ insert_length
      end
    end

    record PositionData, position : Int32, distance_cache : StaticArray(Int32, 4), cost_diff : Float32, cost : Float32

    # The eight start positions with the smallest cost difference.
    class StartPositionQueue
      @queue = StaticArray(PositionData, 8).new(PositionData.new(0, StaticArray(Int32, 4).new(0), 0_f32, 0_f32))
      @index = 0

      def clear : Nil
        @index = 0
      end

      def size : Int32
        Math.min(@index, 8)
      end

      def push(data : PositionData) : Nil
        offset = ~@index & 7
        @index += 1
        length = size
        @queue[offset] = data
        (1...length).each do
          if @queue[offset & 7].cost_diff > @queue[(offset + 1) & 7].cost_diff
            @queue[offset & 7], @queue[(offset + 1) & 7] = @queue[(offset + 1) & 7], @queue[offset & 7]
          end
          offset += 1
        end
      end

      @[AlwaysInline]
      def at(k : Int32) : PositionData
        @queue[(k - @index) & 7]
      end
    end

    # Bit costs of literals (cumulative per position), commands and
    # distances.
    class CostModel
      getter command_costs = Slice(Float32).new(NUM_COMMAND_SYMBOLS, 0_f32)
      getter distance_costs : Slice(Float32)
      getter literal_costs : Slice(Float32)
      getter min_command_cost = 0_f32

      def initialize(distance_alphabet : Int32, @num_bytes : Int32)
        @distance_costs = Slice(Float32).new(distance_alphabet, 0_f32)
        @literal_costs = Slice(Float32).new(@num_bytes + 2, 0_f32)
      end

      @[AlwaysInline]
      def literal_costs(from : Int32, to : Int32) : Float32
        @literal_costs.to_unsafe[to] - @literal_costs.to_unsafe[from]
      end

      def self.set_cost(histogram : Pointer(UInt32), size : Int32, literal : Bool, cost : Pointer(Float32)) : Nil
        sum = 0_u64
        size.times { |i| sum += histogram[i] }
        log2sum = Encode.fast_log2(sum).to_f32
        missing = sum
        unless literal
          size.times { |i| missing += 1 if histogram[i] == 0 }
        end
        missing_cost = Encode.fast_log2(missing).to_f32 + 2
        size.times do |i|
          if histogram[i] == 0
            cost[i] = missing_cost
            next
          end
          cost[i] = log2sum - Encode.fast_log2(histogram[i]).to_f32
          cost[i] = 1_f32 if cost[i] < 1
        end
      end

      def set_from_commands(data : UInt8*, position : Int32, commands : CommandBuffer, first : Int32,
                            last_insert_length : Int32) : Nil
        literal_histogram = StaticArray(UInt32, 256).new(0_u32)
        command_histogram = StaticArray(UInt32, 704).new(0_u32)
        distance_histogram = StaticArray(UInt32, 544).new(0_u32)
        literal_cost = StaticArray(Float32, 256).new(0_f32)
        pos = position - last_insert_length
        (first...commands.size).each do |i|
          entry = commands[i]
          command_histogram[entry.command_prefix] += 1
          distance_histogram[entry.distance_prefix & 0x3FF] += 1 if entry.command_prefix >= 128
          entry.insert_length.times { |j| literal_histogram[data[pos + j]] += 1 }
          pos += entry.insert_length.to_i32 + entry.copy_length.to_i32
        end
        CostModel.set_cost(literal_histogram.to_unsafe, 256, true, literal_cost.to_unsafe)
        CostModel.set_cost(command_histogram.to_unsafe, NUM_COMMAND_SYMBOLS, false, @command_costs.to_unsafe)
        CostModel.set_cost(distance_histogram.to_unsafe, @distance_costs.size, false, @distance_costs.to_unsafe)
        @min_command_cost = @command_costs.min
        carry = 0_f32
        costs = @literal_costs.to_unsafe
        costs[0] = 0_f32
        @num_bytes.times do |i|
          carry += literal_cost[data[position + i]]
          costs[i + 1] = costs[i] + carry
          carry -= costs[i + 1] - costs[i]
        end
      end

      def set_from_literal_costs(data : UInt8*, position : Int32) : Nil
        costs = @literal_costs.to_unsafe
        LiteralCost.estimate(data + position, @num_bytes, costs + 1)
        costs[0] = 0_f32
        carry = 0_f32
        @num_bytes.times do |i|
          carry += costs[i + 1]
          costs[i + 1] = costs[i] + carry
          carry -= costs[i + 1] - costs[i]
        end
        NUM_COMMAND_SYMBOLS.times { |i| @command_costs[i] = Encode.fast_log2(11 + i).to_f32 }
        @distance_costs.size.times { |i| @distance_costs[i] = Encode.fast_log2(20 + i).to_f32 }
        @min_command_cost = Encode.fast_log2(11).to_f32
      end
    end

    @[AlwaysInline]
    private def self.update_node(nodes : Node*, pos : Int32, start : Int32, length : Int32, length_code : Int32,
                                 distance : UInt32, short_code : Int32, cost : Float32) : Nil
      node = nodes + pos + length
      node.value.length = (length.to_u32 | ((length + 9 - length_code).to_u32 << 25))
      node.value.distance = distance
      node.value.dcode_insert_length = (short_code.to_u32 << 27) | (pos - start).to_u32
      node.value.cost = cost
    end

    private def self.compute_minimum_copy_length(start_cost : Float32, nodes : Node*, num_bytes : Int32, pos : Int32) : Int32
      min_cost = start_cost
      length = 2
      next_length_bucket = 4
      next_length_offset = 10
      while pos + length <= num_bytes && nodes[pos + length].cost <= min_cost
        length += 1
        if length == next_length_offset
          min_cost += 1_f32
          next_length_offset += next_length_bucket
          next_length_bucket *= 2
        end
      end
      length
    end

    private def self.compute_distance_shortcut(block_start : Int64, pos : Int32, max_backward_limit : Int32,
                                               nodes : Node*) : UInt32
      node = nodes[pos]
      c_len = node.copy_length.to_i64
      i_len = node.insert_length.to_i64
      dist = node.distance.to_i64
      if pos == 0
        0_u32
      elsif dist + c_len <= block_start + pos && dist <= max_backward_limit && node.distance_code > 0
        pos.to_u32
      else
        nodes[pos - c_len - i_len].link
      end
    end

    private def self.compute_distance_cache(pos : Int32, starting_cache : Int32*, nodes : Node*) : StaticArray(Int32, 4)
      cache = StaticArray(Int32, 4).new(0)
      index = 0
      p = nodes[pos].link.to_i32
      while index < 4 && p > 0
        node = nodes[p]
        cache[index] = node.distance.to_i32!
        index += 1
        p = nodes[p - node.copy_length.to_i32 - node.insert_length.to_i32].link.to_i32
      end
      start = 0
      while index < 4
        cache[index] = starting_cache[start]
        start += 1
        index += 1
      end
      cache
    end

    private def self.evaluate_node(block_start : Int64, pos : Int32, max_backward_limit : Int32, starting_cache : Int32*,
                                   model : CostModel, queue : StartPositionQueue, nodes : Node*) : Nil
      node_cost = nodes[pos].cost
      (nodes + pos).value.link = compute_distance_shortcut(block_start, pos, max_backward_limit, nodes)
      literal = model.literal_costs(0, pos)
      if node_cost <= literal
        queue.push(PositionData.new(pos, compute_distance_cache(pos, starting_cache, nodes), node_cost - literal, node_cost))
      end
    end

    # google/brotli's UpdateNodes: relaxes every command that can end
    # after *pos*; returns the longest copy length used.
    private def self.update_nodes(num_bytes : Int32, block_start : Int32, pos : Int32, data : UInt8*, quality : Int32,
                                  params : DistanceParams, max_backward_limit : Int32, stream_offset : Int64,
                                  starting_cache : Int32*, num_matches : Int32, matches : Pointer(BackwardMatch),
                                  model : CostModel, queue : StartPositionQueue, nodes : Node*) : Int32
      cur_ix = block_start + pos
      max_distance = Math.min(cur_ix, max_backward_limit)
      dictionary_start = Math.min(cur_ix.to_i64 + stream_offset, max_backward_limit.to_i64).to_i32
      max_length = num_bytes - pos
      max_zopfli_length = quality <= 10 ? MAX_ZOPFLI_LENGTH_10 : MAX_ZOPFLI_LENGTH_11
      max_iters = quality <= 10 ? 1 : 5
      result = 0
      evaluate_node(block_start + stream_offset, pos, max_backward_limit, starting_cache, model, queue, nodes)
      first = queue.at(0)
      min_cost = first.cost + model.min_command_cost + model.literal_costs(first.position, pos)
      min_length = compute_minimum_copy_length(min_cost, nodes, num_bytes, pos)
      current = data + cur_ix
      k = 0
      while k < max_iters && k < queue.size
        posdata = queue.at(k)
        start = posdata.position
        insert_code = Encode.insert_length_code((pos - start).to_u32)
        start_costdiff = posdata.cost_diff
        base_cost = start_costdiff + INSERT_EXTRA[insert_code].to_f32 + model.literal_costs(0, pos)
        best_length = min_length - 1
        j = 0
        while j < NUM_DISTANCE_SHORT_CODES && best_length < max_length
          backward = posdata.distance_cache[DISTANCE_CACHE_INDEX[j]].to_i64 + DISTANCE_CACHE_OFFSET[j]
          j_current = j
          j += 1
          next if backward > dictionary_start
          next unless backward <= max_distance
          next if backward <= 0
          previous = current - backward
          continuation = current[best_length]
          next if continuation != previous[best_length]
          length = Encode.match_length(previous, current, max_length)
          dist_cost = base_cost + model.distance_costs.to_unsafe[j_current]
          l = best_length + 1
          while l <= length
            copy_code = Encode.copy_length_code(l.to_u32)
            command_code = Encode.combine_length_codes(insert_code, copy_code, j_current == 0)
            cost = (command_code < 128 ? base_cost : dist_cost) + COPY_EXTRA[copy_code].to_f32 +
                   model.command_costs.to_unsafe[command_code]
            if cost < nodes[pos + l].cost
              update_node(nodes, pos, start, l, l, backward.to_u32, j_current + 1, cost)
              result = l if l > result
            end
            best_length = l
            l += 1
          end
        end
        if k >= 2
          k += 1
          next
        end
        length = min_length
        num_matches.times do |m|
          match = matches[m]
          dist = match.distance
          dictionary_match = dist.to_i64 > dictionary_start
          dist_symbol, _ = Encode.prefix_encode_distance(dist &+ NUM_DISTANCE_SHORT_CODES &- 1, params.direct_codes, params.postfix_bits)
          dist_cost = base_cost + (dist_symbol >> 10).to_f32 + model.distance_costs.to_unsafe[dist_symbol & 0x3FF]
          max_match_length = match.length
          if length < max_match_length && (dictionary_match || max_match_length > max_zopfli_length)
            length = max_match_length
          end
          while length <= max_match_length
            length_code = dictionary_match ? match.length_code : length
            copy_code = Encode.copy_length_code(length_code.to_u32)
            command_code = Encode.combine_length_codes(insert_code, copy_code, false)
            cost = dist_cost + COPY_EXTRA[copy_code].to_f32 + model.command_costs.to_unsafe[command_code]
            if cost < nodes[pos + length].cost
              update_node(nodes, pos, start, length, length_code, dist, 0, cost)
              result = length if length > result
            end
            length += 1
          end
        end
        k += 1
      end
      result
    end

    private def self.compute_shortest_path_from_nodes(num_bytes : Int32, nodes : Node*) : Int32
      index = num_bytes
      num_commands = 0
      while nodes[index].insert_length == 0 && nodes[index].length == 1
        index -= 1
      end
      (nodes + index).value.link = UInt32::MAX
      while index != 0
        length = nodes[index].command_length.to_i32
        index -= length
        (nodes + index).value.link = length.to_u32
        num_commands += 1
      end
      num_commands
    end

    # Appends the commands of the path; returns the leftover insert length
    # and the literals the commands took (google/brotli's
    # BrotliZopfliCreateCommands).
    def self.create_commands(num_bytes : Int32, block_start : Int32, nodes : Node*, cache : Int32*,
                             last_insert_length : Int32, params : DistanceParams, window_bits : Int32,
                             stream_offset : Int64, commands : CommandBuffer) : {Int32, Int64}
      max_backward_limit = (1 << window_bits) - WINDOW_GAP
      pos = 0
      offset = nodes[0].link
      literals = 0_i64
      first = true
      while offset != UInt32::MAX
        node = nodes[pos + offset.to_i32]
        copy_length = node.copy_length.to_i32
        insert_length = node.insert_length.to_i32
        pos += insert_length
        offset = node.link
        if first
          insert_length += last_insert_length
          last_insert_length = 0
          first = false
        end
        distance = node.distance.to_i32!
        length_code = node.length_code.to_i32
        dictionary_start = Math.min(block_start.to_i64 + pos + stream_offset, max_backward_limit.to_i64)
        dictionary = node.distance.to_i64 > dictionary_start
        distance_code = node.distance_code
        commands.push(Command.copy(insert_length.to_u32, copy_length.to_u32, length_code - copy_length, distance_code, params))
        if !dictionary && distance_code > 0
          cache[3] = cache[2]
          cache[2] = cache[1]
          cache[1] = cache[0]
          cache[0] = distance
        end
        literals += insert_length
        pos += copy_length
      end
      {last_insert_length + num_bytes - pos, literals}
    end

    private def self.init_nodes(nodes : Slice(Node)) : Nil
      nodes.fill(Node.new)
    end

    # Quality 10 (google/brotli's BrotliCreateZopfliBackwardReferences).
    def self.create_backward_references(num_bytes : Int32, position : Int32, data : UInt8*, quality : Int32,
                                        window_bits : Int32, stream_offset : Int64, params : DistanceParams,
                                        hasher : BinaryTreeHasher, cache : Int32*, last_insert_length : Int32,
                                        commands : CommandBuffer) : {Int32, Int64}
      nodes_slice = Slice(Node).new(num_bytes + 1, Node.new)
      nodes = nodes_slice.to_unsafe
      max_backward_limit = (1 << window_bits) - WINDOW_GAP
      max_zopfli_length = quality <= 10 ? MAX_ZOPFLI_LENGTH_10 : MAX_ZOPFLI_LENGTH_11
      matches = Slice(BackwardMatch).new(2 * (BinaryTreeHasher::MAX_NUM_MATCHES + 64), BackwardMatch.new(0_u32, 0_u32))
      store_end = num_bytes >= hasher.store_lookahead ? position + num_bytes - hasher.store_lookahead + 1 : position
      (nodes + 0).value.length = 0_u32
      (nodes + 0).value.cost = 0_f32
      model = CostModel.new(params.alphabet_size.to_i32, num_bytes)
      model.set_from_literal_costs(data, position)
      queue = StartPositionQueue.new
      i = 0
      while i + hasher.hash_type_length - 1 < num_bytes
        pos = position + i
        max_distance = Math.min(pos, max_backward_limit)
        dictionary_start = Math.min(pos.to_i64 + stream_offset, max_backward_limit.to_i64).to_i32
        num_matches = hasher.find_all_matches(data, pos, num_bytes - i, max_distance, dictionary_start,
          params.max_distance.to_i32, quality, matches.to_unsafe)
        if num_matches > 0 && matches[num_matches - 1].length > max_zopfli_length
          matches[0] = matches[num_matches - 1]
          num_matches = 1
        end
        skip = update_nodes(num_bytes, position, i, data, quality, params, max_backward_limit, stream_offset, cache,
          num_matches, matches.to_unsafe, model, queue, nodes)
        skip = 0 if skip < LONG_COPY_QUICK_STEP
        skip = Math.max(matches[0].length, skip) if num_matches == 1 && matches[0].length > max_zopfli_length
        if skip > 1
          hasher.store_range(data, pos + 1, Math.min(pos + skip, store_end))
          skip -= 1
          while skip > 0
            i += 1
            break if i + hasher.hash_type_length - 1 >= num_bytes
            evaluate_node(position.to_i64 + stream_offset, i, max_backward_limit, cache, model, queue, nodes)
            skip -= 1
          end
        end
        i += 1
      end
      compute_shortest_path_from_nodes(num_bytes, nodes)
      create_commands(num_bytes, position, nodes, cache, last_insert_length, params, window_bits, stream_offset, commands)
    end

    # Quality 11 (google/brotli's BrotliCreateHqZopfliBackwardReferences):
    # every match is collected once, then the path is searched twice, the
    # second time with costs from the first path's commands.
    def self.create_hq_backward_references(num_bytes : Int32, position : Int32, data : UInt8*, quality : Int32,
                                           window_bits : Int32, stream_offset : Int64, params : DistanceParams,
                                           hasher : BinaryTreeHasher, cache : Int32*, last_insert_length : Int32,
                                           commands : CommandBuffer) : {Int32, Int64}
      max_backward_limit = (1 << window_bits) - WINDOW_GAP
      num_matches = Slice(UInt32).new(num_bytes, 0_u32)
      matches = Array(BackwardMatch).new(4 * num_bytes + BinaryTreeHasher::MAX_NUM_MATCHES)
      store_end = num_bytes >= hasher.store_lookahead ? position + num_bytes - hasher.store_lookahead + 1 : position
      scratch = Slice(BackwardMatch).new(BinaryTreeHasher::MAX_NUM_MATCHES + 64, BackwardMatch.new(0_u32, 0_u32))
      i = 0
      while i + hasher.hash_type_length - 1 < num_bytes
        pos = position + i
        max_distance = Math.min(pos, max_backward_limit)
        dictionary_start = Math.min(pos.to_i64 + stream_offset, max_backward_limit.to_i64).to_i32
        found = hasher.find_all_matches(data, pos, num_bytes - i, max_distance, dictionary_start,
          params.max_distance.to_i32, quality, scratch.to_unsafe)
        num_matches[i] = found.to_u32
        if found > 0
          match_length = scratch[found - 1].length
          if match_length > MAX_ZOPFLI_LENGTH_11
            skip = match_length - 1
            matches << scratch[found - 1]
            num_matches[i] = 1_u32
            hasher.store_range(data, pos + 1, Math.min(pos + match_length, store_end))
            stop = Math.min(i + 1 + skip, num_bytes)
            (i + 1...stop).each { |z| num_matches[z] = 0_u32 }
            i += skip
          else
            found.times { |m| matches << scratch[m] }
          end
        end
        i += 1
      end
      orig_last_insert_length = last_insert_length
      orig_cache = StaticArray(Int32, 4).new { |slot| cache[slot] }
      orig_num_commands = commands.size
      nodes_slice = Slice(Node).new(num_bytes + 1, Node.new)
      nodes = nodes_slice.to_unsafe
      model = CostModel.new(params.alphabet_size.to_i32, num_bytes)
      matches_pointer = matches.to_unsafe
      result = {0, 0_i64}
      2.times do |pass|
        init_nodes(nodes_slice)
        if pass == 0
          model.set_from_literal_costs(data, position)
        else
          model.set_from_commands(data, position, commands, orig_num_commands, orig_last_insert_length)
        end
        commands.truncate(orig_num_commands)
        4.times { |slot| cache[slot] = orig_cache[slot] }
        zopfli_iterate(num_bytes, position, data, quality, params, max_backward_limit, stream_offset, cache, model,
          num_matches, matches_pointer, nodes)
        result = create_commands(num_bytes, position, nodes, cache, orig_last_insert_length, params, window_bits,
          stream_offset, commands)
      end
      result
    end

    private def self.zopfli_iterate(num_bytes : Int32, position : Int32, data : UInt8*, quality : Int32,
                                    params : DistanceParams, max_backward_limit : Int32, stream_offset : Int64,
                                    cache : Int32*, model : CostModel, num_matches : Slice(UInt32),
                                    matches : Pointer(BackwardMatch), nodes : Node*) : Int32
      max_zopfli_length = quality <= 10 ? MAX_ZOPFLI_LENGTH_10 : MAX_ZOPFLI_LENGTH_11
      queue = StartPositionQueue.new
      cur_match_pos = 0
      (nodes + 0).value.length = 0_u32
      (nodes + 0).value.cost = 0_f32
      i = 0
      while i + 3 < num_bytes
        count = num_matches[i].to_i32
        skip = update_nodes(num_bytes, position, i, data, quality, params, max_backward_limit, stream_offset, cache,
          count, matches + cur_match_pos, model, queue, nodes)
        skip = 0 if skip < LONG_COPY_QUICK_STEP
        cur_match_pos += count
        if count == 1 && matches[cur_match_pos - 1].length > max_zopfli_length
          skip = Math.max(matches[cur_match_pos - 1].length, skip)
        end
        if skip > 1
          skip -= 1
          while skip > 0
            i += 1
            break if i + 3 >= num_bytes
            evaluate_node(position.to_i64 + stream_offset, i, max_backward_limit, cache, model, queue, nodes)
            cur_match_pos += num_matches[i].to_i32
            skip -= 1
          end
        end
        i += 1
      end
      compute_shortest_path_from_nodes(num_bytes, nodes)
    end
  end
end
