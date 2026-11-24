module Amber::Mica::Brotli::Encode
  # The block splitter of qualities 10 and 11 (google/brotli's
  # block_splitter.c): seeds entropy codes from random samples, finds the
  # cheapest path through them with a block switch cost, refines, then
  # clusters the blocks into at most 256 types.
  module BlockSplitter
    LITERAL_SWITCH_COST        = 28.1
    COMMAND_SWITCH_COST        = 13.5
    DISTANCE_SWITCH_COST       = 14.6
    LITERAL_STRIDE             =   70
    COMMAND_STRIDE             =   40
    DISTANCE_STRIDE            =   40
    SYMBOLS_PER_LITERAL_HISTO  =  544
    SYMBOLS_PER_COMMAND_HISTO  =  530
    SYMBOLS_PER_DISTANCE_HISTO =  544
    MIN_LENGTH_FOR_BLOCK_SPLIT =  128
    ITER_MUL_FOR_REFINING      =    2
    MIN_ITERS_FOR_REFINING     =  100
    MAX_LITERAL_HISTOGRAMS     =  100
    MAX_COMMAND_HISTOGRAMS     =   50
    HISTOGRAMS_PER_BATCH       =   64
    CLUSTERS_PER_BATCH         =   16

    # Splits the literals, command symbols and distance symbols of
    # *commands* (google/brotli's BrotliSplitBlock).
    def self.split_block(commands : CommandBuffer, data : UInt8*, position : Int32, quality : Int32) : {BlockSplit, BlockSplit, BlockSplit}
      literal_count = 0
      commands.size.times { |i| literal_count += commands[i].insert_length.to_i32 }
      literals = Bytes.new(literal_count)
      at = 0
      from = position
      commands.size.times do |i|
        entry = commands[i]
        insert = entry.insert_length.to_i32
        (literals.to_unsafe + at).copy_from(data + from, insert)
        at += insert
        from += insert + entry.copy_length.to_i32
      end
      literal_split = split_byte_vector(literals.to_unsafe, literal_count, NUM_LITERAL_SYMBOLS, SYMBOLS_PER_LITERAL_HISTO,
        MAX_LITERAL_HISTOGRAMS, LITERAL_STRIDE, LITERAL_SWITCH_COST, quality)
      codes = Slice(UInt16).new(commands.size) { |i| commands[i].command_prefix }
      command_split = split_byte_vector(codes.to_unsafe, codes.size, NUM_COMMAND_SYMBOLS, SYMBOLS_PER_COMMAND_HISTO,
        MAX_COMMAND_HISTOGRAMS, COMMAND_STRIDE, COMMAND_SWITCH_COST, quality)
      distances = Slice(UInt16).new(commands.size, 0_u16)
      count = 0
      commands.size.times do |i|
        entry = commands[i]
        if entry.copy_length != 0 && entry.command_prefix >= 128
          distances[count] = entry.distance_prefix & 0x3FF
          count += 1
        end
      end
      distance_split = split_byte_vector(distances.to_unsafe, count, NUM_HISTOGRAM_DISTANCES, SYMBOLS_PER_DISTANCE_HISTO,
        MAX_COMMAND_HISTOGRAMS, DISTANCE_STRIDE, DISTANCE_SWITCH_COST, quality)
      {literal_split, command_split, distance_split}
    end

    @[AlwaysInline]
    private def self.my_rand(seed : UInt32) : UInt32
      seed &* 16807_u32
    end

    private def self.add_vector(set : HistogramSet, index : Int32, data : T*, length : Int32) : Nil forall T
      histogram = set[index]
      length.times { |i| histogram[data[i]] &+= 1 }
      set.totals[index] &+= length
    end

    private def self.split_byte_vector(data : T*, length : Int32, data_size : Int32, symbols_per_histogram : Int32,
                                       max_histograms : Int32, stride : Int32, block_switch_cost : Float64,
                                       quality : Int32) : BlockSplit forall T
      num_histograms = Math.min(length // symbols_per_histogram + 1, max_histograms)
      split = BlockSplit.new(1)
      if length == 0
        split.num_types = 1
        return split
      end
      if length < MIN_LENGTH_FOR_BLOCK_SPLIT
        split.num_types = 1
        split.types[0] = 0_u8
        split.lengths[0] = length.to_u32
        split.num_blocks = 1
        return split
      end
      histograms = HistogramSet.new(data_size, num_histograms + 1)
      tmp = num_histograms
      # Initial entropy codes.
      seed = 7_u32
      block_length = length // num_histograms
      num_histograms.times do |i|
        pos = (length.to_i64 * i // num_histograms).to_i32
        if i != 0
          seed = my_rand(seed)
          pos += (seed % block_length).to_i32
        end
        pos = length - stride - 1 if pos + stride >= length
        add_vector(histograms, i, data + pos, stride)
      end
      # Refine.
      iters = ITER_MUL_FOR_REFINING * length // stride + MIN_ITERS_FOR_REFINING
      iters = ((iters + num_histograms - 1) // num_histograms) * num_histograms
      seed = 7_u32
      iters.times do |iter|
        histograms.clear(tmp)
        sample_stride = stride
        pos = 0
        if sample_stride >= length
          sample_stride = length
        else
          seed = my_rand(seed)
          pos = (seed % (length - sample_stride + 1)).to_i32
        end
        add_vector(histograms, tmp, data + pos, sample_stride)
        histograms.add_histogram(iter % num_histograms, histograms, tmp)
      end
      block_ids = Bytes.new(length)
      bitmap_len = (num_histograms + 7) >> 3
      insert_cost = Slice(Float64).new(data_size * num_histograms, 0.0)
      cost = Slice(Float64).new(num_histograms, 0.0)
      switch_signal = Bytes.new(length * bitmap_len)
      new_id = Slice(UInt16).new(num_histograms, 0_u16)
      num_blocks = 0
      (quality < 11 ? 3 : 10).times do
        num_blocks = find_blocks(data, length, block_switch_cost, num_histograms, histograms, insert_cost, cost,
          switch_signal, block_ids)
        num_histograms = remap_block_ids(block_ids, length, new_id, num_histograms)
        num_histograms.times { |i| histograms.clear(i) }
        length.times { |i| histograms.add(block_ids[i], data[i]) }
      end
      cluster_blocks(data, length, num_blocks, block_ids, data_size)
    end

    private def self.find_blocks(data : T*, length : Int32, block_switch_bitcost : Float64, num_histograms : Int32,
                                 histograms : HistogramSet, insert_cost : Slice(Float64), cost : Slice(Float64),
                                 switch_signal : Bytes, block_id : Bytes) : Int32 forall T
      alphabet_size = histograms.data_size
      bitmap_len = (num_histograms + 7) >> 3
      if num_histograms <= 1
        block_id[0, length].fill(0_u8)
        return 1
      end
      insert_cost.fill(0.0)
      num_histograms.times { |i| insert_cost[i] = Encode.fast_log2(histograms.totals[i].to_u32!) }
      i = alphabet_size
      while i != 0
        i -= 1
        num_histograms.times do |j|
          count = histograms[j][i]
          insert_cost[i * num_histograms + j] = insert_cost[j] - (count == 0 ? -2.0 : Encode.fast_log2(count))
        end
      end
      cost.fill(0.0)
      switch_signal[0, length * bitmap_len].fill(0_u8)
      costs = cost.to_unsafe
      inserts = insert_cost.to_unsafe
      length.times do |byte_ix|
        ix = byte_ix * bitmap_len
        insert_cost_ix = data[byte_ix].to_i32 * num_histograms
        min_cost = 1e99
        switch_cost = block_switch_bitcost
        num_histograms.times do |k|
          costs[k] += inserts[insert_cost_ix + k]
          if costs[k] < min_cost
            min_cost = costs[k]
            block_id[byte_ix] = k.to_u8
          end
        end
        switch_cost *= 0.77 + (0.07 / 2000) * byte_ix if byte_ix < 2000
        num_histograms.times do |k|
          costs[k] -= min_cost
          if costs[k] >= switch_cost
            costs[k] = switch_cost
            switch_signal[ix + (k >> 3)] |= (1 << (k & 7)).to_u8
          end
        end
      end
      num_blocks = 1
      byte_ix = length - 1
      ix = byte_ix * bitmap_len
      current = block_id[byte_ix]
      while byte_ix > 0
        mask = (1 << (current & 7)).to_u8
        byte_ix -= 1
        ix -= bitmap_len
        if switch_signal[ix + (current >> 3)] & mask != 0
          if current != block_id[byte_ix]
            current = block_id[byte_ix]
            num_blocks += 1
          end
        end
        block_id[byte_ix] = current
      end
      num_blocks
    end

    private def self.remap_block_ids(block_ids : Bytes, length : Int32, new_id : Slice(UInt16), num_histograms : Int32) : Int32
      invalid = 256_u16
      num_histograms.times { |i| new_id[i] = invalid }
      next_id = 0_u16
      length.times do |i|
        if new_id[block_ids[i]] == invalid
          new_id[block_ids[i]] = next_id
          next_id += 1
        end
      end
      length.times { |i| block_ids[i] = new_id[block_ids[i]].to_u8 }
      next_id.to_i32
    end

    private def self.cluster_blocks(data : T*, length : Int32, num_blocks : Int32, block_ids : Bytes,
                                    data_size : Int32) : BlockSplit forall T
      histogram_symbols = Slice(UInt32).new(num_blocks, 0_u32)
      block_lengths = Slice(UInt32).new(num_blocks, 0_u32)
      expected_num_clusters = CLUSTERS_PER_BATCH * (num_blocks + HISTOGRAMS_PER_BATCH - 1) // HISTOGRAMS_PER_BATCH
      all_histograms = [] of HistogramSet
      cluster_size_list = [] of UInt32
      num_clusters = 0
      batch = HistogramSet.new(data_size, Math.min(num_blocks, HISTOGRAMS_PER_BATCH))
      max_num_pairs = HISTOGRAMS_PER_BATCH * HISTOGRAMS_PER_BATCH // 2
      pairs = Slice(Cluster::Pair).new(max_num_pairs + 1, Cluster::Pair.new(0_u32, 0_u32, 0.0, 0.0))
      tmp = HistogramSet.new(data_size, 2)
      sizes = Slice(UInt32).new(HISTOGRAMS_PER_BATCH, 0_u32)
      new_clusters = Slice(UInt32).new(HISTOGRAMS_PER_BATCH, 0_u32)
      symbols = Slice(UInt32).new(HISTOGRAMS_PER_BATCH, 0_u32)
      remap = Slice(UInt32).new(HISTOGRAMS_PER_BATCH, 0_u32)
      block_index = 0
      length.times do |i|
        block_lengths[block_index] += 1
        block_index += 1 if i + 1 == length || block_ids[i] != block_ids[i + 1]
      end
      pos = 0
      i = 0
      while i < num_blocks
        num_to_combine = Math.min(num_blocks - i, HISTOGRAMS_PER_BATCH)
        num_to_combine.times do |j|
          batch.clear(j)
          block_lengths[i + j].times do
            batch.add(j, data[pos])
            pos += 1
          end
          batch.bit_costs[j] = Cluster.population_cost(batch, j)
          new_clusters[j] = j.to_u32
          symbols[j] = j.to_u32
          sizes[j] = 1_u32
        end
        num_new_clusters = Cluster.combine(batch, tmp, sizes, symbols.to_unsafe, new_clusters.to_unsafe, pairs,
          num_to_combine, num_to_combine, HISTOGRAMS_PER_BATCH, max_num_pairs)
        num_new_clusters.times do |j|
          single = HistogramSet.new(data_size, 1)
          single.copy(0, batch, new_clusters[j])
          all_histograms << single
          cluster_size_list << sizes[new_clusters[j]]
          remap[new_clusters[j]] = j.to_u32
        end
        num_to_combine.times { |j| histogram_symbols[i + j] = num_clusters.to_u32 + remap[symbols[j]] }
        num_clusters += num_new_clusters
        i += HISTOGRAMS_PER_BATCH
      end
      everything = HistogramSet.new(data_size, num_clusters)
      num_clusters.times { |j| everything.copy(j, all_histograms[j], 0) }
      cluster_size = Slice(UInt32).new(num_clusters) { |j| cluster_size_list[j] }
      max_num_pairs = Math.min(64 * num_clusters, (num_clusters // 2) * num_clusters)
      if pairs.size < max_num_pairs + 1
        pairs = Slice(Cluster::Pair).new(max_num_pairs + 1, Cluster::Pair.new(0_u32, 0_u32, 0.0, 0.0))
      end
      clusters = Slice(UInt32).new(num_clusters) { |j| j.to_u32 }
      num_final_clusters = Cluster.combine(everything, tmp, cluster_size, histogram_symbols.to_unsafe, clusters.to_unsafe,
        pairs, num_clusters, num_blocks, MAX_BLOCK_TYPES, max_num_pairs)
      invalid = UInt32::MAX
      new_index = Slice(UInt32).new(num_clusters, invalid)
      pos = 0
      next_index = 0_u32
      num_blocks.times do |block|
        tmp.clear(0)
        block_lengths[block].times do
          tmp.add(0, data[pos])
          pos += 1
        end
        best_out = block == 0 ? histogram_symbols[0] : histogram_symbols[block - 1]
        best_bits = bit_cost_distance_to(tmp, everything, best_out)
        num_final_clusters.times do |j|
          bits = bit_cost_distance_to(tmp, everything, clusters[j])
          if bits < best_bits
            best_bits = bits
            best_out = clusters[j]
          end
        end
        histogram_symbols[block] = best_out
        if new_index[best_out] == invalid
          new_index[best_out] = next_index
          next_index += 1
        end
      end
      split = BlockSplit.new(num_blocks)
      current_length = 0_u32
      block_index = 0
      max_type = 0_u8
      num_blocks.times do |block|
        current_length += block_lengths[block]
        if block + 1 == num_blocks || histogram_symbols[block] != histogram_symbols[block + 1]
          id = new_index[histogram_symbols[block]].to_u8
          split.types[block_index] = id
          split.lengths[block_index] = current_length
          max_type = id if id > max_type
          current_length = 0_u32
          block_index += 1
        end
      end
      split.num_blocks = block_index
      split.num_types = max_type.to_i32 + 1
      split
    end

    # The cost of histogram 0 of *tmp* moved into *candidate* of *set*,
    # using histogram 1 of *tmp* as scratch.
    private def self.bit_cost_distance_to(tmp : HistogramSet, set : HistogramSet, candidate : UInt32) : Float64
      return 0.0 if tmp.totals[0] == 0
      tmp.copy(1, tmp, 0)
      tmp.add_histogram(1, set, candidate)
      Cluster.population_cost(tmp, 1) - set.bit_costs[candidate]
    end
  end
end
