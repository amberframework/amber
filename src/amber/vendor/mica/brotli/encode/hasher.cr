lib LibBrotliEncodeIntrinsics
  fun prefetch = "llvm.prefetch.p0"(address : Void*, rw : Int32, locality : Int32, cache_type : Int32) : Void
end

module Amber::Mica::Brotli::Encode
  # Asks the CPU to start loading the cache line at *address* for a read.
  @[AlwaysInline]
  def self.prefetch(address : Pointer) : Nil
    LibBrotliEncodeIntrinsics.prefetch(address.as(Void*), 0, 3, 1)
  end

  # google/brotli's backward reference score: a byte of match is worth
  # 135, a doubling of the distance costs 30.
  SCORE_BASE           = 1920_i64
  LITERAL_BYTE_SCORE   =  135_i64
  DISTANCE_BIT_PENALTY =   30_i64
  MIN_SCORE            = SCORE_BASE &+ 100

  HASH_MUL32 =         0x1E35A7BD_u32
  HASH_MUL64 = 0x1FE35A7BD3579BD3_u64

  # The best match a search found: length, length code minus length (a
  # dictionary word cut short), distance and score.
  struct SearchResult
    property length : Int32
    property length_code_delta : Int32
    property distance : Int32
    property score : Int64

    def initialize(@length = 0, @length_code_delta = 0, @distance = 0, @score = MIN_SCORE)
    end
  end

  @[AlwaysInline]
  def self.load32(data : UInt8*) : UInt32
    data.as(UInt32*).value
  end

  @[AlwaysInline]
  def self.load64(data : UInt8*) : UInt64
    data.as(UInt64*).value
  end

  @[AlwaysInline]
  def self.backward_reference_score(length : Int32, distance : Int32) : Int64
    SCORE_BASE &+ LITERAL_BYTE_SCORE &* length &- DISTANCE_BIT_PENALTY &* log2_floor(distance.to_u32!)
  end

  @[AlwaysInline]
  def self.score_using_last_distance(length : Int32) : Int64
    LITERAL_BYTE_SCORE &* length &+ SCORE_BASE &+ 15
  end

  @[AlwaysInline]
  def self.penalty_using_last_distance(short_code : Int32) : Int64
    39_i64 &+ ((0x1CA10 >> (short_code & 0xE)) & 0xE)
  end

  # The length of the common prefix of *s1* and *s2*, at most *limit*.
  @[AlwaysInline]
  def self.match_length(s1 : UInt8*, s2 : UInt8*, limit : Int32) : Int32
    matched = 0
    # Sixteen bytes a turn while there is room: long runs (images, padding)
    # spend most of their search time here.
    while limit &- matched >= 16
      difference = load64(s2 + matched) ^ load64(s1 + matched)
      return matched &+ (difference.trailing_zeros_count >> 3).to_i32! if difference != 0
      difference = load64(s2 + (matched &+ 8)) ^ load64(s1 + (matched &+ 8))
      return matched &+ 8 &+ (difference.trailing_zeros_count >> 3).to_i32! if difference != 0
      matched &+= 16
    end
    while limit &- matched >= 8
      difference = load64(s2 + matched) ^ load64(s1 + matched)
      return matched &+ (difference.trailing_zeros_count >> 3).to_i32! if difference != 0
      matched &+= 8
    end
    while matched < limit && s1[matched] == s2[matched]
      matched &+= 1
    end
    matched
  end

  # Fills the slots after the last four distances with the near misses
  # of the last two (google/brotli's PrepareDistanceCache).
  @[AlwaysInline]
  def self.prepare_distance_cache(cache : Int32*, count : Int32) : Nil
    return unless count > 4
    last = cache[0]
    cache[4] = last &- 1
    cache[5] = last &+ 1
    cache[6] = last &- 2
    cache[7] = last &+ 2
    cache[8] = last &- 3
    cache[9] = last &+ 3
    return unless count > 10
    next_last = cache[1]
    cache[10] = next_last &- 1
    cache[11] = next_last &+ 1
    cache[12] = next_last &- 2
    cache[13] = next_last &+ 2
    cache[14] = next_last &- 3
    cache[15] = next_last &+ 3
  end

  # Raw memory for hash tables, outside the garbage collector (they hold
  # no references, and megabytes of collected memory per encode would set
  # off a collection each time): not cleared, since the hashers track
  # which slots hold positions. Hand it back with `free_table`.
  @[AlwaysInline]
  def self.table(type : T.class, count : Int32) : Pointer(T) forall T
    bytes = LibC::SizeT.new(Math.max(count, 1)) * sizeof(T)
    memory = LibC.malloc(bytes)
    raise RuntimeError.new("Brotli encoder could not allocate #{bytes} bytes") if memory.null?
    memory.as(Pointer(T))
  end

  def self.free_table(table : Pointer(T)) : Pointer(T) forall T
    LibC.free(table.as(Void*)) unless table.null?
    Pointer(T).null
  end

  # Matches against the RFC 7932 static dictionary through a hash of each
  # word's first four bytes (google/brotli's SearchInStaticDictionary),
  # giving up once fewer than 1 in 128 lookups finds a word.
  class DictionarySearch
    BUCKETS = 32768
    # Cut-off transforms 0 to 9: the transform that drops the last N
    # bytes of a word, packed six bits each.
    CUTOFF_TRANSFORMS = 0x071B520ADA2D3200_u64
    CUTOFF_COUNT      =                     10

    # google/brotli's kStaticDictionaryHashWords and ...Lengths: two
    # slots per hash bucket, the second for words shorter than 8 bytes.
    TABLES = build_tables

    @lookups = 0_i64
    @matches = 0_i64

    @[AlwaysInline]
    def search(data : UInt8*, max_length : Int32, max_backward : Int32, max_distance : Int32,
               result : SearchResult*, shallow : Bool) : Nil
      return if @matches < (@lookups >> 7)
      words, lengths = TABLES
      key = (Encode.hash14(data) << 1).to_i32!
      (shallow ? 1 : 2).times do |slot|
        @lookups &+= 1
        length = lengths.unsafe_fetch(key &+ slot).to_i32!
        next if length == 0
        @matches &+= 1 if test_item(length, words.unsafe_fetch(key &+ slot).to_i32!, data, max_length, max_backward, max_distance, result)
      end
    end

    @[AlwaysInline]
    private def test_item(length : Int32, word : Int32, data : UInt8*, max_length : Int32, max_backward : Int32,
                          max_distance : Int32, result : SearchResult*) : Bool
      return false if length > max_length
      offset = Dictionary::OFFSETS_BY_LENGTH[length] &+ length &* word
      matched = Encode.match_length(data, Dictionary::DATA.to_unsafe + offset, length)
      return false if matched &+ CUTOFF_COUNT <= length || matched == 0
      cut = length &- matched
      transform = (cut << 2) &+ ((CUTOFF_TRANSFORMS >> (cut &* 6)) & 0x3F).to_i32!
      backward = max_backward.to_i64! &+ 1 &+ word &+ (transform.to_i64! << Dictionary::SIZE_BITS_BY_LENGTH[length])
      return false if backward > max_distance
      score = Encode.backward_reference_score(matched, backward.to_i32!)
      return false if score < result.value.score
      result.value = SearchResult.new(matched, length &- matched, backward.to_i32!, score)
      true
    end

    private def self.build_tables : {Slice(UInt16), Bytes}
      words = Slice(UInt16).new(BUCKETS, 0_u16)
      lengths = Bytes.new(BUCKETS, 0_u8)
      data = Dictionary::DATA.to_unsafe
      index = 0
      Dictionary::MAX_WORD_LENGTH.downto(Dictionary::MIN_WORD_LENGTH) do |length|
        short = length < 8 ? 1 : 0
        count = 1 << Dictionary::SIZE_BITS_BY_LENGTH[length]
        start = data + Dictionary::OFFSETS_BY_LENGTH[length]
        count.times do |reverse|
          word = count - 1 - reverse
          slot = ((Encode.hash14(start + length * word) << 1) + short).to_i32
          if lengths[slot] & 0x80 == 0
            final = FROZEN[index >> 3] & (1 << (index & 7)) != 0
            words[slot] = word.to_u16
            lengths[slot] = (length + (final ? 0x80 : 0)).to_u8
          end
          index += 1
        end
      end
      lengths.map! { |value| value & 0x7F }
      {words, lengths}
    end

    # google/brotli's frozen_idx (dictionary_hash.c): which word of each
    # bucket slot wins, one bit per word in the order the table is built.
    FROZEN = StaticArray[
      0_u8, 0_u8, 8_u8, 164_u8, 32_u8, 56_u8, 31_u8, 191_u8, 36_u8, 4_u8, 128_u8, 81_u8, 68_u8, 132_u8, 145_u8, 129_u8, 0_u8, 0_u8, 0_u8, 28_u8, 0_u8, 8_u8, 1_u8, 1_u8,
      64_u8, 3_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 64_u8, 1_u8, 2_u8, 128_u8, 0_u8, 132_u8, 49_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      17_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 36_u8, 152_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 8_u8, 0_u8, 0_u8, 128_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 64_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 64_u8, 133_u8, 0_u8, 32_u8, 0_u8, 0_u8, 128_u8, 1_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 4_u8, 4_u8, 4_u8, 32_u8, 16_u8, 130_u8, 0_u8, 128_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 0_u8, 64_u8, 0_u8, 160_u8, 0_u8, 148_u8, 53_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 0_u8, 130_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 48_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      32_u8, 1_u8, 32_u8, 129_u8, 0_u8, 12_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 16_u8, 32_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 0_u8, 0_u8, 2_u8, 66_u8, 128_u8,
      0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 1_u8, 6_u8, 128_u8, 8_u8, 0_u8, 192_u8, 24_u8, 32_u8, 0_u8, 0_u8, 8_u8, 4_u8, 128_u8, 128_u8, 2_u8, 160_u8,
      0_u8, 160_u8, 0_u8, 64_u8, 0_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 1_u8, 0_u8, 0_u8, 64_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 66_u8, 0_u8, 2_u8, 0_u8, 4_u8, 0_u8, 8_u8, 0_u8, 2_u8, 0_u8, 0_u8, 33_u8, 8_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 128_u8,
      162_u8, 4_u8, 128_u8, 0_u8, 2_u8, 33_u8, 0_u8, 160_u8, 0_u8, 8_u8, 0_u8, 64_u8, 0_u8, 160_u8, 0_u8, 129_u8, 4_u8, 0_u8, 0_u8, 32_u8, 0_u8, 0_u8, 32_u8, 0_u8,
      2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 10_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 64_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 16_u8, 0_u8, 16_u8, 16_u8, 0_u8, 0_u8, 80_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 16_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 8_u8,
      64_u8, 128_u8, 0_u8, 0_u8, 0_u8, 8_u8, 208_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 8_u8,
      0_u8, 128_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 16_u8, 8_u8, 1_u8, 136_u8, 0_u8, 0_u8, 36_u8, 0_u8, 64_u8, 9_u8, 0_u8, 1_u8, 32_u8, 8_u8, 0_u8,
      64_u8, 64_u8, 131_u8, 16_u8, 224_u8, 32_u8, 4_u8, 0_u8, 4_u8, 5_u8, 160_u8, 0_u8, 131_u8, 0_u8, 4_u8, 96_u8, 0_u8, 0_u8, 184_u8, 192_u8, 0_u8, 177_u8, 205_u8, 96_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 2_u8, 0_u8, 32_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 0_u8, 0_u8, 128_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 1_u8, 4_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 64_u8, 69_u8, 0_u8, 0_u8, 8_u8,
      2_u8, 66_u8, 32_u8, 64_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 128_u8, 17_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 12_u8,
      0_u8, 16_u8, 0_u8, 0_u8, 4_u8, 128_u8, 64_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 224_u8, 0_u8, 8_u8, 0_u8, 0_u8, 130_u8, 16_u8, 64_u8, 128_u8,
      2_u8, 64_u8, 0_u8, 0_u8, 0_u8, 128_u8, 2_u8, 192_u8, 64_u8, 0_u8, 65_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 32_u8, 4_u8, 2_u8, 2_u8, 76_u8, 0_u8,
      0_u8, 0_u8, 4_u8, 72_u8, 52_u8, 131_u8, 44_u8, 76_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 1_u8, 16_u8, 148_u8, 4_u8, 0_u8, 16_u8, 10_u8, 64_u8, 0_u8, 2_u8, 0_u8,
      1_u8, 0_u8, 128_u8, 64_u8, 68_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 144_u8, 0_u8, 8_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 3_u8, 64_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 128_u8, 0_u8, 0_u8, 32_u8, 66_u8, 0_u8, 0_u8, 0_u8, 40_u8, 0_u8, 18_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 33_u8, 0_u8, 0_u8,
      32_u8, 0_u8, 0_u8, 32_u8, 0_u8, 128_u8, 4_u8, 64_u8, 145_u8, 140_u8, 0_u8, 0_u8, 0_u8, 128_u8, 0_u8, 2_u8, 0_u8, 0_u8, 20_u8, 0_u8, 80_u8, 38_u8, 0_u8, 0_u8,
      32_u8, 0_u8, 32_u8, 64_u8, 4_u8, 4_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8, 129_u8, 4_u8, 0_u8, 0_u8, 144_u8, 17_u8, 32_u8, 130_u8, 16_u8, 132_u8, 24_u8, 134_u8, 0_u8,
      0_u8, 64_u8, 2_u8, 5_u8, 50_u8, 8_u8, 194_u8, 33_u8, 1_u8, 68_u8, 117_u8, 1_u8, 8_u8, 32_u8, 161_u8, 54_u8, 0_u8, 130_u8, 34_u8, 0_u8, 0_u8, 0_u8, 64_u8, 128_u8,
      0_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 1_u8, 0_u8, 0_u8, 0_u8, 3_u8, 14_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 16_u8, 4_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 96_u8, 1_u8, 24_u8, 18_u8, 0_u8, 1_u8, 128_u8, 24_u8, 0_u8, 64_u8, 0_u8, 4_u8, 0_u8, 16_u8, 128_u8, 0_u8, 64_u8, 0_u8, 0_u8,
      0_u8, 64_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 66_u8, 128_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 16_u8, 0_u8, 64_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 6_u8, 0_u8, 8_u8, 8_u8, 2_u8, 0_u8, 64_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 2_u8, 2_u8,
      12_u8, 64_u8, 0_u8, 64_u8, 0_u8, 8_u8, 0_u8, 128_u8, 32_u8, 0_u8, 0_u8, 10_u8, 0_u8, 0_u8, 32_u8, 0_u8, 128_u8, 32_u8, 33_u8, 8_u8, 136_u8, 0_u8, 96_u8, 64_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 4_u8, 16_u8, 4_u8, 8_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 2_u8, 0_u8, 0_u8, 1_u8, 128_u8, 0_u8, 64_u8, 16_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 2_u8, 0_u8, 16_u8, 0_u8, 4_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 20_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 136_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 64_u8, 0_u8, 0_u8, 1_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8, 0_u8, 65_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 2_u8, 128_u8, 0_u8, 0_u8, 0_u8, 8_u8, 2_u8, 0_u8, 0_u8, 128_u8, 0_u8, 16_u8, 2_u8, 0_u8, 0_u8, 4_u8,
      0_u8, 32_u8, 0_u8, 0_u8, 1_u8, 4_u8, 64_u8, 64_u8, 0_u8, 4_u8, 0_u8, 1_u8, 0_u8, 16_u8, 0_u8, 32_u8, 68_u8, 4_u8, 4_u8, 65_u8, 10_u8, 0_u8, 20_u8, 37_u8,
      18_u8, 1_u8, 148_u8, 0_u8, 32_u8, 128_u8, 3_u8, 8_u8, 0_u8, 64_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 16_u8, 1_u8, 128_u8, 0_u8, 0_u8, 0_u8,
      128_u8, 16_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 128_u8, 0_u8, 0_u8, 128_u8, 64_u8, 128_u8, 64_u8, 0_u8, 130_u8, 0_u8, 164_u8, 8_u8, 0_u8, 0_u8, 1_u8, 64_u8, 128_u8,
      0_u8, 18_u8, 0_u8, 2_u8, 150_u8, 0_u8, 8_u8, 0_u8, 0_u8, 64_u8, 0_u8, 81_u8, 0_u8, 0_u8, 16_u8, 128_u8, 2_u8, 8_u8, 36_u8, 32_u8, 129_u8, 4_u8, 144_u8, 13_u8,
      0_u8, 0_u8, 3_u8, 8_u8, 1_u8, 0_u8, 2_u8, 0_u8, 0_u8, 64_u8, 0_u8, 5_u8, 0_u8, 1_u8, 34_u8, 1_u8, 32_u8, 2_u8, 16_u8, 128_u8, 128_u8, 128_u8, 0_u8, 0_u8,
      0_u8, 2_u8, 0_u8, 4_u8, 18_u8, 8_u8, 12_u8, 34_u8, 32_u8, 192_u8, 6_u8, 64_u8, 224_u8, 33_u8, 0_u8, 0_u8, 137_u8, 72_u8, 64_u8, 0_u8, 24_u8, 8_u8, 128_u8, 128_u8,
      0_u8, 16_u8, 0_u8, 32_u8, 128_u8, 128_u8, 132_u8, 8_u8, 0_u8, 0_u8, 16_u8, 0_u8, 64_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 16_u8, 0_u8, 4_u8, 128_u8, 64_u8, 0_u8,
      0_u8, 1_u8, 0_u8, 4_u8, 64_u8, 32_u8, 144_u8, 130_u8, 2_u8, 128_u8, 0_u8, 192_u8, 0_u8, 64_u8, 82_u8, 64_u8, 1_u8, 32_u8, 128_u8, 128_u8, 2_u8, 0_u8, 84_u8, 0_u8,
      32_u8, 0_u8, 44_u8, 24_u8, 72_u8, 80_u8, 32_u8, 16_u8, 0_u8, 0_u8, 44_u8, 16_u8, 96_u8, 64_u8, 1_u8, 72_u8, 131_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 165_u8,
      0_u8, 129_u8, 2_u8, 49_u8, 48_u8, 64_u8, 64_u8, 12_u8, 64_u8, 176_u8, 64_u8, 84_u8, 8_u8, 128_u8, 20_u8, 64_u8, 213_u8, 136_u8, 104_u8, 1_u8, 41_u8, 15_u8, 83_u8, 170_u8,
      0_u8, 0_u8, 41_u8, 1_u8, 64_u8, 64_u8, 0_u8, 193_u8, 64_u8, 64_u8, 8_u8, 0_u8, 128_u8, 0_u8, 0_u8, 64_u8, 8_u8, 64_u8, 8_u8, 1_u8, 16_u8, 0_u8, 8_u8, 0_u8,
      0_u8, 2_u8, 1_u8, 128_u8, 28_u8, 84_u8, 141_u8, 97_u8, 0_u8, 0_u8, 68_u8, 0_u8, 0_u8, 129_u8, 8_u8, 0_u8, 16_u8, 8_u8, 32_u8, 0_u8, 64_u8, 0_u8, 0_u8, 0_u8,
      24_u8, 0_u8, 0_u8, 0_u8, 192_u8, 0_u8, 8_u8, 128_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 40_u8, 1_u8, 128_u8, 64_u8,
      0_u8, 4_u8, 2_u8, 32_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 32_u8, 8_u8, 0_u8, 32_u8, 0_u8, 0_u8, 0_u8,
      16_u8, 17_u8, 0_u8, 2_u8, 4_u8, 0_u8, 0_u8, 33_u8, 128_u8, 2_u8, 0_u8, 0_u8, 0_u8, 0_u8, 129_u8, 0_u8, 2_u8, 0_u8, 0_u8, 0_u8, 36_u8, 0_u8, 32_u8, 2_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 4_u8, 32_u8, 64_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 32_u8, 0_u8, 0_u8, 32_u8, 128_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 128_u8, 16_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 136_u8, 0_u8, 0_u8, 24_u8, 192_u8, 128_u8, 3_u8, 0_u8, 17_u8, 18_u8, 2_u8, 0_u8, 66_u8, 0_u8, 4_u8, 24_u8, 0_u8, 9_u8,
      208_u8, 167_u8, 0_u8, 144_u8, 20_u8, 64_u8, 0_u8, 130_u8, 64_u8, 0_u8, 2_u8, 16_u8, 136_u8, 8_u8, 74_u8, 32_u8, 0_u8, 168_u8, 0_u8, 65_u8, 32_u8, 8_u8, 12_u8, 1_u8,
      3_u8, 1_u8, 64_u8, 180_u8, 3_u8, 0_u8, 64_u8, 0_u8, 8_u8, 0_u8, 0_u8, 32_u8, 65_u8, 0_u8, 4_u8, 16_u8, 4_u8, 16_u8, 68_u8, 32_u8, 64_u8, 36_u8, 32_u8, 24_u8,
      33_u8, 1_u8, 128_u8, 0_u8, 0_u8, 8_u8, 0_u8, 32_u8, 64_u8, 81_u8, 0_u8, 1_u8, 10_u8, 19_u8, 8_u8, 0_u8, 0_u8, 4_u8, 5_u8, 144_u8, 0_u8, 0_u8, 8_u8, 128_u8,
      0_u8, 0_u8, 4_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 80_u8, 1_u8, 0_u8, 0_u8, 33_u8,
      0_u8, 32_u8, 66_u8, 4_u8, 2_u8, 0_u8, 1_u8, 43_u8, 2_u8, 0_u8, 0_u8, 4_u8, 32_u8, 16_u8, 0_u8, 64_u8, 0_u8, 3_u8, 32_u8, 0_u8, 2_u8, 64_u8, 64_u8, 116_u8,
      0_u8, 65_u8, 52_u8, 64_u8, 0_u8, 17_u8, 64_u8, 192_u8, 96_u8, 8_u8, 10_u8, 8_u8, 2_u8, 4_u8, 0_u8, 17_u8, 64_u8, 0_u8, 4_u8, 0_u8, 0_u8, 4_u8, 128_u8, 0_u8,
      0_u8, 9_u8, 0_u8, 0_u8, 130_u8, 2_u8, 0_u8, 192_u8, 0_u8, 48_u8, 128_u8, 64_u8, 0_u8, 96_u8, 0_u8, 64_u8, 0_u8, 1_u8, 16_u8, 32_u8, 0_u8, 1_u8, 32_u8, 6_u8,
      128_u8, 2_u8, 32_u8, 0_u8, 12_u8, 0_u8, 0_u8, 48_u8, 32_u8, 8_u8, 0_u8, 0_u8, 128_u8, 0_u8, 18_u8, 0_u8, 0_u8, 28_u8, 24_u8, 41_u8, 16_u8, 5_u8, 32_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8,
      0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 0_u8, 64_u8, 0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 16_u8, 128_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 8_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 33_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 16_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    ]
  end

  @[AlwaysInline]
  def self.hash14(data : UInt8*) : UInt32
    (load32(data) &* HASH_MUL32) >> 18
  end

  @[AlwaysInline]
  def self.hash15(data : UInt8*) : UInt32
    (load32(data) &* HASH_MUL32) >> 17
  end
end
