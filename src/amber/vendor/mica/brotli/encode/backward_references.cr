module Amber::Mica::Brotli::Encode
  # The distance code of *distance*: a short code when it is one of the
  # last distances or near the last two, else the distance plus 15
  # (google/brotli's ComputeDistanceCode).
  @[AlwaysInline]
  def self.compute_distance_code(distance : Int32, max_distance : Int32, cache : Int32*) : UInt32
    if distance <= max_distance
      plus3 = distance.to_i64! &+ 3
      offset0 = (plus3 &- cache[0]).to_u64!
      offset1 = (plus3 &- cache[1]).to_u64!
      if distance == cache[0]
        return 0_u32
      elsif distance == cache[1]
        return 1_u32
      elsif offset0 < 7
        return ((0x9750468_u64 >> (4 &* offset0)) & 0xF).to_u32!
      elsif offset1 < 7
        return ((0xFDB1ACE_u64 >> (4 &* offset1)) & 0xF).to_u32!
      elsif distance == cache[2]
        return 2_u32
      elsif distance == cache[3]
        return 3_u32
      end
    end
    (distance &+ NUM_DISTANCE_SHORT_CODES &- 1).to_u32!
  end

  # Greedy-with-lazy-matching LZ77 over `data[position, num_bytes]`
  # (google/brotli's CreateBackwardReferences), appending commands.
  # *insert_length* is the run of literals carried in from the previous
  # block; returns the run left over and the literals the commands took.
  def self.create_backward_references(hasher : H, quality : Int32, window_bits : Int32, data : UInt8*,
                                      position : Int32, num_bytes : Int32, stream_offset : Int64,
                                      params : DistanceParams, cache : Int32*, insert_length : Int32,
                                      commands : CommandBuffer) : {Int32, Int64} forall H
    max_backward_limit = (1 << window_bits) &- WINDOW_GAP
    pos_end = position &+ num_bytes
    lookahead = hasher.store_lookahead
    hash_length = hasher.hash_type_length
    store_end = num_bytes >= lookahead ? position &+ num_bytes &- lookahead &+ 1 : position
    random_window = quality < 9 ? 64 : 512
    apply_random_heuristics = position &+ random_window
    literals = 0_i64
    max_param_distance = params.max_distance.to_i32!
    commands.reserve(num_bytes // 2 &+ 1)
    hasher.prepare_distance_cache(cache)
    while position &+ hash_length < pos_end
      max_length = pos_end &- position
      max_distance = Math.min(position, max_backward_limit)
      dictionary_start = Math.min(position.to_i64! &+ stream_offset, max_backward_limit.to_i64!).to_i32!
      result = SearchResult.new
      hasher.find_longest_match(data, cache, position, max_length, max_distance, dictionary_start,
        max_param_distance, pointerof(result))
      if result.score > MIN_SCORE
        delayed = 0
        max_length &-= 1
        loop do
          later = SearchResult.new(quality < 5 ? Math.min(result.length &- 1, max_length) : 0)
          max_distance = Math.min(position &+ 1, max_backward_limit)
          dictionary_start = Math.min(position.to_i64! &+ 1 &+ stream_offset, max_backward_limit.to_i64!).to_i32!
          hasher.find_longest_match(data, cache, position &+ 1, max_length, max_distance, dictionary_start,
            max_param_distance, pointerof(later))
          if later.score >= result.score &+ 175
            position &+= 1
            insert_length &+= 1
            result = later
            delayed &+= 1
            if delayed < 4 && position &+ hash_length < pos_end
              max_length &-= 1
              next
            end
          end
          break
        end
        apply_random_heuristics = position &+ 2 &* result.length &+ random_window
        dictionary_start = Math.min(position.to_i64! &+ stream_offset, max_backward_limit.to_i64!).to_i32!
        distance_code = compute_distance_code(result.distance, dictionary_start, cache)
        if result.distance <= dictionary_start && distance_code > 0
          cache[3] = cache[2]
          cache[2] = cache[1]
          cache[1] = cache[0]
          cache[0] = result.distance
          hasher.prepare_distance_cache(cache)
        end
        commands.push(Command.copy(insert_length.to_u32!, result.length.to_u32!, result.length_code_delta,
          distance_code, params))
        literals &+= insert_length
        insert_length = 0
        range_start = position &+ 2
        range_end = Math.min(position &+ result.length, store_end)
        if result.distance < (result.length >> 2)
          range_start = Math.min(range_end, Math.max(range_start, position &+ result.length &- (result.distance << 2)))
        end
        hasher.store_range(data, range_start, range_end)
        position &+= result.length
      else
        insert_length &+= 1
        position &+= 1
        if position > apply_random_heuristics
          if position > apply_random_heuristics &+ 4 &* random_window
            margin = Math.max(lookahead &- 1, 4)
            jump = Math.min(position &+ 16, pos_end &- margin)
            while position < jump
              hasher.store(data, position)
              insert_length &+= 4
              position &+= 4
            end
          else
            margin = Math.max(lookahead &- 1, 2)
            jump = Math.min(position &+ 8, pos_end &- margin)
            while position < jump
              hasher.store(data, position)
              insert_length &+= 2
              position &+= 2
            end
          end
        end
      end
    end
    insert_length &+= pos_end &- position
    {insert_length, literals}
  end
end
