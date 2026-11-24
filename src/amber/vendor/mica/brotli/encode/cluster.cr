module Amber::Mica::Brotli::Encode
  # Histogram costs and clustering (google/brotli's bit_cost.c and
  # cluster.c).
  module Cluster
    record Pair, first : UInt32, second : UInt32, cost_combo : Float64, cost_diff : Float64

    # Estimated bits to store histogram *index* of *set* with its prefix
    # code (google/brotli's BrotliPopulationCost).
    def self.population_cost(set : HistogramSet, index : Int) : Float64
      data_size = set.data_size
      histogram = set[index]
      total = set.totals[index]
      return 12.0 if total == 0
      count = 0
      symbols = StaticArray(Int32, 5).new(0)
      data_size.times do |i|
        next unless histogram[i] > 0
        symbols[count] = i
        count += 1
        break if count > 4
      end
      return 12.0 if count == 1
      return 20.0 + total.to_f64 if count == 2
      if count == 3
        a = histogram[symbols[0]]
        b = histogram[symbols[1]]
        c = histogram[symbols[2]]
        return 28.0 + 2.0 * (a.to_u64 + b + c) - Math.max(a, Math.max(b, c))
      end
      if count == 4
        histo = StaticArray(UInt32, 4).new { |i| histogram[symbols[i]] }
        4.times do |i|
          (i + 1...4).each do |j|
            histo[j], histo[i] = histo[i], histo[j] if histo[j] > histo[i]
          end
        end
        h23 = histo[2].to_u64 + histo[3]
        return 37.0 + 3.0 * h23 + 2.0 * (histo[0].to_u64 + histo[1]) - Math.max(h23, histo[0].to_u64)
      end
      bits = 0.0
      max_depth = 1
      depth_histogram = StaticArray(UInt32, 18).new(0_u32)
      log2total = Encode.fast_log2(total)
      i = 0
      while i < data_size
        if histogram[i] > 0
          log2p = log2total - Encode.fast_log2(histogram[i])
          depth = (log2p + 0.5).to_i32
          bits += histogram[i] * log2p
          depth = 15 if depth > 15
          max_depth = depth if depth > max_depth
          depth_histogram[depth] += 1
          i += 1
        else
          reps = 1_u32
          k = i + 1
          while k < data_size && histogram[k] == 0
            reps += 1
            k += 1
          end
          i += reps
          break if i == data_size
          if reps < 3
            depth_histogram[0] += reps
          else
            reps -= 2
            while reps > 0
              depth_histogram[REPEAT_ZERO_LENGTH] += 1
              bits += 3
              reps >>= 3
            end
          end
        end
      end
      bits += 18 + 2 * max_depth
      bits + Encode.bits_entropy(depth_histogram.to_unsafe, CODE_LENGTH_CODES)
    end

    @[AlwaysInline]
    private def self.cluster_cost_diff(size_a : UInt32, size_b : UInt32) : Float64
      size_c = size_a.to_u64 + size_b
      size_a.to_f64 * Encode.fast_log2(size_a) + size_b.to_f64 * Encode.fast_log2(size_b) -
        size_c.to_f64 * Encode.fast_log2(size_c)
    end

    @[AlwaysInline]
    private def self.less?(p1 : Pair, p2 : Pair) : Bool
      return p1.cost_diff > p2.cost_diff if p1.cost_diff != p2.cost_diff
      (p1.second &- p1.first) > (p2.second &- p2.first)
    end

    # Queues the merge of histograms *idx1* and *idx2* of *set* when it
    # looks worthwhile, keeping the best pair first.
    private def self.compare_and_push(set : HistogramSet, tmp : HistogramSet, cluster_size : Slice(UInt32),
                                      idx1 : UInt32, idx2 : UInt32, max_num_pairs : Int32,
                                      pairs : Slice(Pair), num_pairs : Int32) : Int32
      return num_pairs if idx1 == idx2
      idx1, idx2 = idx2, idx1 if idx2 < idx1
      cost_diff = 0.5 * cluster_cost_diff(cluster_size[idx1], cluster_size[idx2])
      cost_diff -= set.bit_costs[idx1]
      cost_diff -= set.bit_costs[idx2]
      good = false
      cost_combo = 0.0
      if set.totals[idx1] == 0
        cost_combo = set.bit_costs[idx2]
        good = true
      elsif set.totals[idx2] == 0
        cost_combo = set.bit_costs[idx1]
        good = true
      else
        threshold = num_pairs == 0 ? 1e99 : Math.max(0.0, pairs[0].cost_diff)
        tmp.copy(0, set, idx1)
        tmp.add_histogram(0, set, idx2)
        combo = population_cost(tmp, 0)
        if combo < threshold - cost_diff
          cost_combo = combo
          good = true
        end
      end
      return num_pairs unless good
      pair = Pair.new(idx1, idx2, cost_combo, cost_diff + cost_combo)
      if num_pairs > 0 && less?(pairs[0], pair)
        if num_pairs < max_num_pairs
          pairs[num_pairs] = pairs[0]
          num_pairs += 1
        end
        pairs[0] = pair
      elsif num_pairs < max_num_pairs
        pairs[num_pairs] = pair
        num_pairs += 1
      end
      num_pairs
    end

    # Greedily merges the histograms named by `clusters[0, num_clusters]`
    # while that saves bits, then down to *max_clusters*; renames merged
    # histograms in `symbols[0, symbols_size]`. Returns the cluster count
    # (google/brotli's BrotliHistogramCombine).
    def self.combine(set : HistogramSet, tmp : HistogramSet, cluster_size : Slice(UInt32), symbols : Pointer(UInt32),
                     clusters : Pointer(UInt32), pairs : Slice(Pair), num_clusters : Int32, symbols_size : Int32,
                     max_clusters : Int32, max_num_pairs : Int32) : Int32
      cost_diff_threshold = 0.0
      min_cluster_size = 1
      num_pairs = 0
      num_clusters.times do |idx1|
        (idx1 + 1...num_clusters).each do |idx2|
          num_pairs = compare_and_push(set, tmp, cluster_size, clusters[idx1], clusters[idx2], max_num_pairs, pairs, num_pairs)
        end
      end
      while num_clusters > min_cluster_size
        if pairs[0].cost_diff >= cost_diff_threshold
          cost_diff_threshold = 1e99
          min_cluster_size = max_clusters
          next
        end
        best_idx1 = pairs[0].first
        best_idx2 = pairs[0].second
        set.add_histogram(best_idx1, set, best_idx2)
        set.bit_costs[best_idx1] = pairs[0].cost_combo
        cluster_size[best_idx1] += cluster_size[best_idx2]
        symbols_size.times { |i| symbols[i] = best_idx1 if symbols[i] == best_idx2 }
        num_clusters.times do |i|
          if clusters[i] == best_idx2
            (clusters + i).move_from(clusters + i + 1, num_clusters - i - 1)
            break
          end
        end
        num_clusters -= 1
        copy_to = 0
        num_pairs.times do |i|
          p = pairs[i]
          next if p.first == best_idx1 || p.second == best_idx1 || p.first == best_idx2 || p.second == best_idx2
          if less?(pairs[0], p)
            front = pairs[0]
            pairs[0] = p
            pairs[copy_to] = front
          else
            pairs[copy_to] = p
          end
          copy_to += 1
        end
        num_pairs = copy_to
        num_clusters.times do |i|
          num_pairs = compare_and_push(set, tmp, cluster_size, best_idx1, clusters[i], max_num_pairs, pairs, num_pairs)
        end
      end
      num_clusters
    end

    # The bits histogram *index* of *source* costs when moved into
    # histogram *candidate* of *set*.
    def self.bit_cost_distance(source : HistogramSet, index : Int, set : HistogramSet, candidate : Int,
                               tmp : HistogramSet) : Float64
      return 0.0 if source.totals[index] == 0
      tmp.copy(0, source, index)
      tmp.add_histogram(0, set, candidate)
      population_cost(tmp, 0) - set.bit_costs[candidate]
    end

    # Clusters `input` into at most *max_histograms* histograms; returns
    # them and the map from each input histogram to its cluster
    # (google/brotli's BrotliClusterHistograms).
    def self.cluster_histograms(input : HistogramSet, max_histograms : Int32) : {HistogramSet, Slice(UInt32)}
      in_size = input.count
      data_size = input.data_size
      cluster_size = Slice(UInt32).new(in_size, 1_u32)
      clusters = Slice(UInt32).new(in_size, 0_u32)
      symbols = Slice(UInt32).new(in_size, 0_u32)
      max_input_histograms = 64
      pairs_capacity = max_input_histograms * max_input_histograms // 2
      pairs = Slice(Pair).new(pairs_capacity + 1, Pair.new(0_u32, 0_u32, 0.0, 0.0))
      tmp = HistogramSet.new(data_size, 1)
      output = HistogramSet.new(data_size, in_size)
      in_size.times do |i|
        output.copy(i, input, i)
        output.bit_costs[i] = population_cost(input, i)
        symbols[i] = i.to_u32
      end
      num_clusters = 0
      i = 0
      while i < in_size
        num_to_combine = Math.min(in_size - i, max_input_histograms)
        num_to_combine.times { |j| clusters[num_clusters + j] = (i + j).to_u32 }
        num_clusters += combine(output, tmp, cluster_size, symbols.to_unsafe + i, clusters.to_unsafe + num_clusters,
          pairs, num_to_combine, num_to_combine, max_histograms, pairs_capacity)
        i += max_input_histograms
      end
      max_num_pairs = Math.min(64 * num_clusters, (num_clusters // 2) * num_clusters)
      if pairs.size < max_num_pairs + 1
        pairs = Slice(Pair).new(max_num_pairs + 1, Pair.new(0_u32, 0_u32, 0.0, 0.0))
      end
      num_clusters = combine(output, tmp, cluster_size, symbols.to_unsafe, clusters.to_unsafe, pairs, num_clusters,
        in_size, max_histograms, max_num_pairs)
      remap(input, clusters, num_clusters, output, tmp, symbols)
      reindexed = reindex(output, symbols)
      {reindexed, symbols}
    end

    # Moves each input histogram to its cheapest cluster and rebuilds the
    # clusters from them (google/brotli's BrotliHistogramRemap).
    private def self.remap(input : HistogramSet, clusters : Slice(UInt32), num_clusters : Int32, output : HistogramSet,
                           tmp : HistogramSet, symbols : Slice(UInt32)) : Nil
      input.count.times do |i|
        best_out = i == 0 ? symbols[0] : symbols[i - 1]
        best_bits = bit_cost_distance(input, i, output, best_out, tmp)
        num_clusters.times do |j|
          bits = bit_cost_distance(input, i, output, clusters[j], tmp)
          if bits < best_bits
            best_bits = bits
            best_out = clusters[j]
          end
        end
        symbols[i] = best_out
      end
      num_clusters.times { |j| output.clear(clusters[j]) }
      input.count.times { |i| output.add_histogram(symbols[i], input, i) }
    end

    # Renumbers the clusters in order of first use and packs them
    # (google/brotli's BrotliHistogramReindex).
    private def self.reindex(output : HistogramSet, symbols : Slice(UInt32)) : HistogramSet
      invalid = UInt32::MAX
      new_index = Slice(UInt32).new(output.count, invalid)
      next_index = 0_u32
      symbols.each do |symbol|
        if new_index[symbol] == invalid
          new_index[symbol] = next_index
          next_index += 1
        end
      end
      packed = HistogramSet.new(output.data_size, next_index.to_i32)
      next_index = 0_u32
      symbols.size.times do |i|
        if new_index[symbols[i]] == next_index
          packed.copy(next_index, output, symbols[i])
          next_index += 1
        end
        symbols[i] = new_index[symbols[i]]
      end
      packed
    end
  end
end
