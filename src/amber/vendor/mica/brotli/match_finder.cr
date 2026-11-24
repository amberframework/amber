module Amber::Mica::Brotli
  # Finds backward matches for the encoder with hash chains over 4-byte
  # prefixes: `heads` holds the latest position per hash, `chain` the
  # previous position with the same hash, as a ring the size of the
  # window. Positions index the encoder's buffer; `shift` rebases them
  # when the streaming writer drops old bytes.
  #
  # :nodoc:
  class MatchFinder
    # Scores follow google/brotli's backward reference score: a byte of
    # match is worth 135, a doubling of the distance costs 30.
    SCORE_BASE    = 1920
    MIN_SCORE     = SCORE_BASE + 100
    LENGTH_WEIGHT = 135
    DISTANCE_BITS =  30

    getter depth : Int32
    @heads : Slice(Int32)
    @chain : Slice(Int32)
    @chain_mask : Int32
    @shift_bits : Int32

    # *depth* is how many chain links a search may follow; 1 keeps only
    # the latest position per hash and allocates no chain.
    def initialize(hash_bits : Int32, chain_size : Int32, @depth : Int32)
      @heads = Slice(Int32).new(1 << hash_bits, -1)
      @shift_bits = 32 - hash_bits
      size = @depth > 1 ? Math.pw2ceil(Math.max(chain_size, 1)) : 1
      @chain = Slice(Int32).new(size, -1)
      @chain_mask = size - 1
    end

    @[AlwaysInline]
    def self.load32(data : Bytes, at : Int32) : UInt32
      (data.to_unsafe + at).as(UInt32*).value
    end

    @[AlwaysInline]
    def self.log2_floor(value : Int32) : Int32
      31 - value.leading_zeros_count
    end

    @[AlwaysInline]
    def self.score(length : Int32, distance : Int32) : Int32
      SCORE_BASE + LENGTH_WEIGHT * length - DISTANCE_BITS * log2_floor(distance)
    end

    @[AlwaysInline]
    private def hash(data : Bytes, at : Int32) : Int32
      ((MatchFinder.load32(data, at) &* 0x1E35A7BD_u32) >> @shift_bits).to_i32
    end

    # Records position *at*; its four bytes must be in *data*.
    @[AlwaysInline]
    def insert(data : Bytes, at : Int32) : Nil
      key = hash(data, at)
      @chain.unsafe_put(at & @chain_mask, @heads.unsafe_fetch(key)) if @depth > 1
      @heads.unsafe_put(key, at)
    end

    # The length of the common prefix of `data[a..]` and `data[b..]`, at
    # most *limit*.
    @[AlwaysInline]
    def self.match_length(data : Bytes, a : Int32, b : Int32, limit : Int32) : Int32
      pointer = data.to_unsafe
      length = 0
      while length + 8 <= limit
        difference = (pointer + a + length).as(UInt64*).value ^ (pointer + b + length).as(UInt64*).value
        return length + (difference.trailing_zeros_count >> 3) if difference != 0
        length += 8
      end
      while length < limit && pointer[a + length] == pointer[b + length]
        length += 1
      end
      length
    end

    # The best-scoring match at *at* of 4 to *limit* bytes no farther back
    # than *max_distance*, as {length, distance, score}; length 0 when
    # none scores over `MIN_SCORE`. Stops early at *nice_length*.
    def find(data : Bytes, at : Int32, limit : Int32, max_distance : Int32, nice_length : Int32) : {Int32, Int32, Int32}
      best_length = 3
      best_distance = 0
      best_score = MIN_SCORE
      candidate = @heads.unsafe_fetch(hash(data, at))
      left = @depth
      pointer = data.to_unsafe
      while candidate >= 0 && left > 0
        distance = at - candidate
        break if distance > max_distance || distance <= 0
        if best_length < limit && pointer[candidate + best_length] == pointer[at + best_length]
          length = MatchFinder.match_length(data, at, candidate, limit)
          if length > best_length
            score = MatchFinder.score(length, distance)
            if score > best_score
              best_score = score
              best_length = length
              best_distance = distance
              break if length >= nice_length
            end
          end
        end
        left -= 1
        break if @depth == 1
        candidate = @chain.unsafe_fetch(candidate & @chain_mask)
        break if at - candidate <= distance
      end
      best_distance == 0 ? {0, 0, 0} : {best_length, best_distance, best_score}
    end

    # Appends to *lengths* and *distances* every match at *at* longer than
    # all closer ones (lengths increase, distances increase), from 4 bytes
    # up to *limit*.
    def find_all(data : Bytes, at : Int32, limit : Int32, max_distance : Int32,
                 lengths : Array(Int32), distances : Array(Int32)) : Nil
      best_length = 3
      candidate = @heads.unsafe_fetch(hash(data, at))
      left = @depth
      pointer = data.to_unsafe
      while candidate >= 0 && left > 0
        distance = at - candidate
        break if distance > max_distance || distance <= 0
        if best_length < limit && pointer[candidate + best_length] == pointer[at + best_length]
          length = MatchFinder.match_length(data, at, candidate, limit)
          if length > best_length
            best_length = length
            lengths << length
            distances << distance
            break if length >= limit
          end
        end
        left -= 1
        break if @depth == 1
        candidate = @chain.unsafe_fetch(candidate & @chain_mask)
        break if at - candidate <= distance
      end
    end

    # Subtracts *offset* from every stored position, dropping those that go
    # below 0, after the writer dropped *offset* bytes from its buffer.
    # *offset* is a multiple of the chain size, so each position keeps its
    # chain slot.
    def shift(offset : Int32) : Nil
      unless @depth == 1 || offset & @chain_mask == 0
        raise ArgumentError.new("Shift offset #{offset} is not a multiple of the chain size")
      end
      @heads.map! { |position| position >= offset ? position - offset : -1 }
      @chain.map! { |position| position >= offset ? position - offset : -1 } if @depth > 1
    end
  end
end
