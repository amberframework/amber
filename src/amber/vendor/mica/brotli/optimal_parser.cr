module Amber::Mica::Brotli
  class Encoder
    # Positions per optimal-parse segment; matches stop at its end.
    SEGMENT = 1 << 16

    # A match this long is taken without searching the positions inside it.
    LONG_MATCH = 325

    # Bit costs of literals, insert-and-copy symbols and distance symbols
    # for the optimal parse, re-estimated from the commands it chooses.
    @literal_cost = Slice(Float32).new(256, 8.0_f32)
    @command_cost = Slice(Float32).new(MetablockWriter::COMMAND_ALPHABET, 8.0_f32)
    @distance_cost = Slice(Float32).new(MetablockWriter::DISTANCE_ALPHABET, 6.0_f32)

    # Matches found per segment position (flat, with offsets).
    @match_offsets = [] of Int32
    @match_lengths = [] of Int32
    @match_distances = [] of Int32
    @word_output = [] of Int32
    @word_length = [] of Int32
    @word_distance = [] of Int32

    # A Zopfli-style shortest path over each segment: every position's
    # matches are collected once, then the cheapest way to reach every
    # position is found by dynamic programming over the cost model; at
    # quality 11 the model is re-estimated from the first path and the
    # path searched again.
    private def optimal_parse(input : Bytes, start : Int32, stop : Int32, stream_offset : Int64) : Nil
      @commands.clear
      estimate_literal_costs(input, start, stop)
      pending = 0
      segment = start
      while segment < stop
        segment_stop = Math.min(segment + SEGMENT, stop)
        collect_matches(input, segment, segment_stop, stream_offset)
        passes = @quality >= 11 ? 2 : 1
        path = [] of {Int32, Int32, Int32, Int32, Bool}
        passes.times do |pass|
          path = shortest_path(input, segment, segment_stop, pending, stream_offset)
          update_costs(path, pending)
        end
        pending = emit_path(path, pending)
        segment = segment_stop
      end
      emit_tail(pending)
    end

    private def estimate_literal_costs(input : Bytes, start : Int32, stop : Int32) : Nil
      counts = StaticArray(Int32, 256).new(0)
      (start...stop).each { |at| counts[input[at]] += 1 }
      total = (stop - start).to_f64
      256.times do |byte|
        @literal_cost[byte] = (counts[byte] == 0 ? Math.log2(total) + 2 : Math.log2(total / counts[byte])).to_f32
      end
    end

    private def collect_matches(input : Bytes, start : Int32, stop : Int32, stream_offset : Int64) : Nil
      @match_offsets.clear
      @match_lengths.clear
      @match_distances.clear
      @word_output.clear
      @word_length.clear
      @word_distance.clear
      skip_until = start
      (start...stop).each do |position|
        @match_offsets << @match_lengths.size
        limit = stop - position
        if position < skip_until || limit < MIN_LENGTH
          @word_output << 0
          @word_length << 0
          @word_distance << 0
          next
        end
        insert_until(input, position)
        max_distance = max_distance_at(stream_offset, position)
        first = @match_lengths.size
        @finder.find_all(input, position, limit, max_distance, @match_lengths, @match_distances)
        insert_until(input, position + 1)
        output, word_length, word_id, _score =
          DictionaryMatcher.find(input, position, limit, max_distance, MatchFinder::MIN_SCORE)
        @word_output << output
        @word_length << word_length
        @word_distance << (output > 0 ? max_distance + 1 + word_id : 0)
        if @match_lengths.size > first && @match_lengths[-1] >= LONG_MATCH
          skip_until = position + @match_lengths[-1]
        end
      end
      @match_offsets << @match_lengths.size
    end

    @[AlwaysInline]
    private def copy_cost(literals : Int32, length : Int32, copy : Int32, distance : Int32, last : Int32) : Float32
      insert_code = EncoderCodes.insert_code(literals)
      copy_code = EncoderCodes.copy_code(copy)
      implicit = distance == last
      symbol = EncoderCodes.command_symbol(insert_code, copy_code, implicit)
      cost = @command_cost.unsafe_fetch(symbol) + Decoder::INSERT_EXTRA[insert_code] + Decoder::COPY_EXTRA[copy_code]
      return cost if symbol < 128
      return cost + @distance_cost[0] if implicit
      code, extra_bits, _extra = EncoderCodes.distance_symbol(distance)
      cost + @distance_cost.unsafe_fetch(code) + extra_bits
    end

    # The cheapest path through `input[start, stop)`, as steps {literal
    # run, output, copy, distance, dictionary?}; the last step may have
    # output 0 (trailing literals).
    private def shortest_path(input : Bytes, start : Int32, stop : Int32, pending : Int32, stream_offset : Int64) : Array({Int32, Int32, Int32, Int32, Bool})
      count = stop - start
      cost = Slice(Float32).new(count + 1, Float32::MAX)
      step_output = Slice(Int32).new(count + 1, 0)
      step_copy = Slice(Int32).new(count + 1, 0)
      step_distance = Slice(Int32).new(count + 1, 0)
      step_word = Slice(Bool).new(count + 1, false)
      literals = Slice(Int32).new(count + 1, 0)
      last = Slice(Int32).new(count + 1, 0)
      cost[0] = 0
      literals[0] = pending
      last[0] = @cache[0]
      count.times do |index|
        here = cost[index]
        position = start + index
        through = here + @literal_cost.unsafe_fetch(input[position])
        if through < cost[index + 1]
          cost[index + 1] = through
          step_output[index + 1] = 0
          literals[index + 1] = literals[index] + 1
          last[index + 1] = last[index]
        end
        limit = count - index
        next if limit < 2
        run = literals[index]
        previous = last[index]
        # The last distance, which costs no distance symbol.
        if previous <= max_distance_at(stream_offset, position)
          length = MatchFinder.match_length(input, position, position - previous, Math.min(limit, 2 * LONG_MATCH))
          ((length >= LONG_MATCH ? length : 2)..length).each do |copy|
            relax(cost, index, copy, copy, previous, false, here + copy_cost(run, copy, copy, previous, previous),
              step_output, step_copy, step_distance, step_word, literals, last)
          end
        end
        shortest = MIN_LENGTH
        (@match_offsets[index]...@match_offsets[index + 1]).each do |slot|
          length = @match_lengths[slot]
          distance = @match_distances[slot]
          from = length >= LONG_MATCH ? length : shortest
          (from..length).each do |copy|
            relax(cost, index, copy, copy, distance, false, here + copy_cost(run, copy, copy, distance, previous),
              step_output, step_copy, step_distance, step_word, literals, last)
          end
          shortest = length + 1
        end
        output = @word_output[index]
        if output > 0
          word_length = @word_length[index]
          distance = @word_distance[index]
          relax(cost, index, output, word_length, distance, true, here + copy_cost(run, output, word_length, distance, -1),
            step_output, step_copy, step_distance, step_word, literals, last)
        end
      end
      copies = [] of {Int32, Int32, Int32, Int32, Bool}
      index = count
      while index > 0
        output = step_output[index]
        if output == 0
          index -= 1
          next
        end
        copies << {index - output, output, step_copy[index], step_distance[index], step_word[index]}
        index -= output
      end
      copies.reverse!
      path = [] of {Int32, Int32, Int32, Int32, Bool}
      at = 0
      copies.each do |from, output, copy, distance, is_word|
        path << {from - at, output, copy, distance, is_word}
        at = from + output
      end
      path << {count - at, 0, 0, 0, false}
      path
    end

    @[AlwaysInline]
    private def relax(cost : Slice(Float32), index : Int32, output : Int32, copy : Int32, distance : Int32,
                      is_word : Bool, total : Float32, step_output : Slice(Int32), step_copy : Slice(Int32),
                      step_distance : Slice(Int32), step_word : Slice(Bool), literals : Slice(Int32),
                      last : Slice(Int32)) : Nil
      target = index + output
      return unless total < cost[target]
      cost[target] = total
      step_output[target] = output
      step_copy[target] = copy
      step_distance[target] = distance
      step_word[target] = is_word
      literals[target] = 0
      last[target] = is_word ? last[index] : distance
    end

    # Re-estimates the command and distance costs from *path*.
    private def update_costs(path : Array({Int32, Int32, Int32, Int32, Bool}), pending : Int32) : Nil
      commands = Slice(UInt32).new(MetablockWriter::COMMAND_ALPHABET, 0_u32)
      distances = Slice(UInt32).new(MetablockWriter::DISTANCE_ALPHABET, 0_u32)
      last = @cache[0]
      path.each_with_index do |step, at|
        run, output, copy, distance, is_word = step
        run += pending if at == 0
        next if output == 0
        implicit = distance == last && !is_word
        symbol = EncoderCodes.command_symbol(EncoderCodes.insert_code(run), EncoderCodes.copy_code(copy), implicit)
        commands[symbol] += 1
        unless symbol < 128
          code = implicit ? 0 : EncoderCodes.distance_symbol(distance)[0]
          distances[code] += 1
        end
        last = distance unless is_word
      end
      fill_costs(@command_cost, commands)
      fill_costs(@distance_cost, distances)
    end

    private def fill_costs(costs : Slice(Float32), counts : Slice(UInt32)) : Nil
      total = counts.sum(0_i64) { |count| count.to_i64 }
      return if total == 0
      missing = (Math.log2(total.to_f64) + 2).to_f32
      counts.each_with_index do |count, symbol|
        costs[symbol] = count == 0 ? missing : Math.log2(total / count.to_f64).to_f32
      end
    end

    # Emits *path* as commands; returns the literals left at its end.
    private def emit_path(path : Array({Int32, Int32, Int32, Int32, Bool}), pending : Int32) : Int32
      path.each_with_index do |step, at|
        run, output, copy, distance, is_word = step
        run += pending if at == 0
        if output == 0
          return run
        end
        emit(run, Match.new(output, copy, distance, 0, is_word))
      end
      0
    end
  end
end
