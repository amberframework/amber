module Amber::Mica::Brotli
  # Finds static dictionary references for the encoder: words of the RFC
  # 7932 dictionary that match the input, used whole (transform 0) or
  # with their last 1 to 9 bytes omitted. Words are indexed by a hash of
  # their first four bytes, longest first.
  #
  # :nodoc:
  module DictionaryMatcher
    HASH_BITS = 15

    # The transform that omits the last N bytes with no prefix or suffix,
    # for N from 0 (identity) to 9.
    OMIT_LAST_TRANSFORM = begin
      ids = StaticArray(Int32, 10).new(-1)
      Tables::TRANSFORMS.each_with_index do |transform, id|
        next unless transform.prefix.empty? && transform.suffix.empty? && transform.kind <= 9
        ids[transform.kind] = id if ids[transform.kind] < 0
      end
      ids
    end

    # Bucket starts (size 2^HASH_BITS + 1) and entries `length << 16 | index`.
    INDEX = build_index

    private def self.build_index : {Slice(Int32), Slice(UInt32)}
      keys = [] of {Int32, UInt32}
      (Dictionary::MIN_WORD_LENGTH..Dictionary::MAX_WORD_LENGTH).each do |length|
        bits = Dictionary::SIZE_BITS_BY_LENGTH[length].to_i32
        next if bits == 0
        (1 << bits).times do |index|
          offset = Dictionary::OFFSETS_BY_LENGTH[length] + index * length
          keys << {hash(Dictionary::DATA, offset), (length.to_u32 << 16) | index.to_u32}
        end
      end
      # Longest words first within a bucket; ties by index.
      keys.sort_by! { |key, entry| {key, -(entry >> 16).to_i32, entry & 0xFFFF} }
      starts = Slice(Int32).new((1 << HASH_BITS) + 1, 0)
      keys.each { |key, _| starts[key + 1] += 1 }
      (1..(1 << HASH_BITS)).each { |bucket| starts[bucket] += starts[bucket - 1] }
      entries = Slice(UInt32).new(keys.size) { |at| keys[at][1] }
      {starts, entries}
    end

    @[AlwaysInline]
    def self.hash(bytes : Bytes, at : Int32) : Int32
      ((MatchFinder.load32(bytes, at) &* 0x1E35A7BD_u32) >> (32 - HASH_BITS)).to_i32
    end

    # The best dictionary reference at *at* producing at most *limit*
    # bytes, as {output length, word length, word id, score} for a
    # reference whose distance is `max_distance + 1 + word id`; output
    # length 0 when none scores over *min_score*.
    def self.find(input : Bytes, at : Int32, limit : Int32, max_distance : Int32, min_score : Int32) : {Int32, Int32, Int32, Int32}
      starts, entries = INDEX
      bucket = hash(input, at)
      best = {0, 0, 0, min_score}
      dictionary = Dictionary::DATA.to_unsafe
      text = input.to_unsafe + at
      (starts[bucket]...starts[bucket + 1]).each do |slot|
        entry = entries[slot]
        length = (entry >> 16).to_i32
        index = (entry & 0xFFFF).to_i32
        word = dictionary + Dictionary::OFFSETS_BY_LENGTH[length] + index * length
        common = 0
        reach = Math.min(length, limit)
        while common < reach && word[common] == text[common]
          common += 1
        end
        omitted = length - common
        next if common < 4 || omitted > 9
        transform = OMIT_LAST_TRANSFORM[omitted]
        next if transform < 0
        word_id = index + (transform << Dictionary::SIZE_BITS_BY_LENGTH[length])
        distance = max_distance + 1 + word_id
        score = MatchFinder.score(common, distance) - (omitted > 0 ? 20 : 0)
        best = {common, length, word_id, score} if score > best[3]
      end
      best
    end
  end
end
