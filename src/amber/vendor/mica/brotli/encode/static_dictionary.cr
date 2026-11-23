module Amber::Mica::Brotli::Encode
  # Every static dictionary match at a position, with transforms, for the
  # optimal parse of qualities 10 and 11 (google/brotli's
  # BrotliFindAllStaticDictionaryMatches over its kStaticDictionaryBuckets
  # lookup table, built here from the dictionary as google/brotli's
  # static initializer does).
  module StaticDictionary
    MAX_MATCH_LENGTH  =                     37
    INVALID_MATCH     =          0xFFFFFFF_u32
    NUM_BUCKETS       =                  32768
    NUM_ITEMS         =                  31705
    IDENTITY          =                      0
    UPPERCASE_FIRST   =                     10
    UPPERCASE_ALL     =                     11
    CUTOFF_TRANSFORMS = 0x071B520ADA2D3200_u64

    # A word of a bucket: length (bit 7 ends the bucket), transform, index.
    record Word, length : UInt8, transform : UInt8, index : UInt16

    LOOKUP = build_lookup

    private def self.word_at(length : Int32, index : Int32) : UInt8*
      Dictionary::DATA.to_unsafe + Dictionary::OFFSETS_BY_LENGTH[length] + length * index
    end

    private def self.build_lookup : {Slice(UInt16), Slice(Word)}
      slots = Slice(Word).new(NUM_ITEMS, Word.new(0_u8, 0_u8, 0_u16))
      heads = Slice(UInt16).new(NUM_BUCKETS, 0_u16)
      counts = Slice(UInt16).new(NUM_BUCKETS, 0_u16)
      previous = Slice(UInt16).new(NUM_ITEMS, 0_u16)
      next_slot = 0
      transformed = StaticArray(UInt8, 24).new(0_u8)
      transformed_other = StaticArray(UInt8, 24).new(0_u8)
      add = ->(length : Int32, transform : Int32, index : Int32, key : UInt32) do
        slots[next_slot] = Word.new(length.to_u8, transform.to_u8, index.to_u16)
        previous[next_slot] = heads[key]
        heads[key] = next_slot.to_u16
        counts[key] += 1
        next_slot += 1
      end
      (4..24).each do |length|
        count = 1 << Dictionary::SIZE_BITS_BY_LENGTH[length]
        count.times do |index|
          add.call(length, IDENTITY, index, Encode.hash15(word_at(length, index)))
        end
        count.times do |index|
          word = word_at(length, index)
          next if word[0] < 'a'.ord || word[0] > 'z'.ord
          length.times { |k| transformed[k] = word[k] }
          transformed[0] = transformed[0] - 32
          key = Encode.hash15(transformed.to_unsafe)
          prefix = Encode.load32(transformed.to_unsafe) & ~0x20202020_u32
          found = false
          current = heads[key].to_i32
          while current != 0
            break if slots[current].length != length
            other = word_at(length, slots[current].index.to_i32)
            if prefix == (Encode.load32(other) & ~0x20202020_u32)
              if (0...length).all? { |k| transformed[k] == other[k] }
                found = true
                break
              end
            end
            current = previous[current].to_i32
          end
          next if found
          add.call(length, UPPERCASE_FIRST, index, key)
        end
        count.times do |index|
          word = word_at(length, index)
          ascii = true
          has_lower = false
          length.times do |k|
            ascii = false if word[k] >= 128
            has_lower = true if k > 0 && word[k] >= 'a'.ord && word[k] <= 'z'.ord
          end
          next if !ascii || !has_lower
          length.times { |k| transformed[k] = word[k] }
          prefix = Encode.load32(transformed.to_unsafe) & ~0x20202020_u32
          length.times do |k|
            transformed[k] = transformed[k] - 32 if transformed[k] >= 'a'.ord && transformed[k] <= 'z'.ord
          end
          key = Encode.hash15(transformed.to_unsafe)
          found = false
          current = heads[key].to_i32
          while current != 0
            slot = slots[current]
            break if slot.length != length
            other = word_at(length, slot.index.to_i32)
            if prefix == (Encode.load32(other) & ~0x20202020_u32)
              if slot.transform == IDENTITY
                if (0...length).all? { |k| transformed[k] == other[k] }
                  found = true
                  break
                end
              elsif slot.transform == UPPERCASE_FIRST
                if transformed[0] == other[0] &- 32 && (1...length).all? { |k| transformed[k] == other[k] }
                  found = true
                  break
                end
              else
                length.times do |k|
                  transformed_other[k] = other[k] >= 'a'.ord && other[k] <= 'z'.ord ? other[k] - 32 : other[k]
                end
                if (0...length).all? { |k| transformed[k] == transformed_other[k] }
                  found = true
                  break
                end
              end
            end
            current = previous[current].to_i32
          end
          next if found
          add.call(length, UPPERCASE_ALL, index, key)
        end
      end
      raise "Static dictionary lookup has #{next_slot} words, expected 31704" unless next_slot == 31704
      buckets = Slice(UInt16).new(NUM_BUCKETS, 0_u16)
      words = Slice(Word).new(NUM_ITEMS, Word.new(0_u8, 0_u8, 0_u16))
      position = 1
      NUM_BUCKETS.times do |bucket|
        num_words = counts[bucket].to_i32
        next if num_words == 0
        buckets[bucket] = position.to_u16
        current = heads[bucket].to_i32
        position += num_words
        num_words.times do |k|
          words[position - 1 - k] = slots[current]
          current = previous[current].to_i32
        end
        last = words[position - 1]
        words[position - 1] = Word.new(last.length | 0x80, last.transform, last.index)
      end
      {buckets, words}
    end

    @[AlwaysInline]
    private def self.add_match(distance : Int, length : Int, length_code : Int, matches : UInt32*) : Nil
      match = ((distance.to_u32 << 5) &+ length_code.to_u32)
      matches[length] = match if match < matches[length]
    end

    private def self.matches?(length : Int32, transform : UInt8, index : Int32, data : UInt8*, max_length : Int32) : Bool
      return false if length > max_length
      word = word_at(length, index)
      if transform == IDENTITY
        Encode.match_length(word, data, length) == length
      elsif transform == UPPERCASE_FIRST
        word[0] >= 'a'.ord && word[0] <= 'z'.ord && (word[0] ^ 32) == data[0] &&
          Encode.match_length(word + 1, data + 1, length - 1) == length - 1
      else
        length.times do |i|
          if word[i] >= 'a'.ord && word[i] <= 'z'.ord
            return false if (word[i] ^ 32) != data[i]
          else
            return false if word[i] != data[i]
          end
        end
        true
      end
    end

    # Fills `matches[length]` (lengths *min_length* to 37) with the
    # smallest (word id << 5 | length code) of a dictionary match of that
    # length at *data*; returns whether any was found.
    def self.find_all(data : UInt8*, min_length : Int32, max_length : Int32, matches : UInt32*) : Bool
      buckets, words = LOOKUP
      found = false
      offset = buckets[Encode.hash15(data)].to_i32
      done = offset == 0
      until done
        w = words[offset]
        offset += 1
        l = (w.length & 0x1F).to_i32
        n = 1 << Dictionary::SIZE_BITS_BY_LENGTH[l]
        id = w.index.to_i32
        done = w.length & 0x80 != 0
        if w.transform == IDENTITY
          matchlen = Encode.match_length(word_at(l, id), data, Math.min(l, max_length))
          if matchlen == l
            add_match(id, l, l, matches)
            found = true
          end
          if matchlen >= l - 1
            add_match(id + 12 * n, l - 1, l, matches)
            if l + 2 < max_length && data[l - 1] == 'i'.ord && data[l] == 'n'.ord && data[l + 1] == 'g'.ord && data[l + 2] == ' '.ord
              add_match(id + 49 * n, l + 3, l, matches)
            end
            found = true
          end
          minlen = min_length
          minlen = Math.max(minlen, l - 9) if l > 9
          maxlen = Math.min(matchlen, l - 2)
          (minlen..maxlen).each do |len|
            cut = l - len
            transform_id = (cut << 2) + ((CUTOFF_TRANSFORMS >> (cut * 6)) & 0x3F).to_i32
            add_match(id + transform_id * n, len, l, matches)
            found = true
          end
          next if matchlen < l || l + 6 >= max_length
          s = data + l
          case s[0]
          when ' '.ord
            add_match(id + n, l + 1, l, matches)
            case s[1]
            when 'a'.ord
              if s[2] == ' '.ord
                add_match(id + 28 * n, l + 3, l, matches)
              elsif s[2] == 's'.ord
                add_match(id + 46 * n, l + 4, l, matches) if s[3] == ' '.ord
              elsif s[2] == 't'.ord
                add_match(id + 60 * n, l + 4, l, matches) if s[3] == ' '.ord
              elsif s[2] == 'n'.ord
                add_match(id + 10 * n, l + 5, l, matches) if s[3] == 'd'.ord && s[4] == ' '.ord
              end
            when 'b'.ord
              add_match(id + 38 * n, l + 4, l, matches) if s[2] == 'y'.ord && s[3] == ' '.ord
            when 'i'.ord
              if s[2] == 'n'.ord
                add_match(id + 16 * n, l + 4, l, matches) if s[3] == ' '.ord
              elsif s[2] == 's'.ord
                add_match(id + 47 * n, l + 4, l, matches) if s[3] == ' '.ord
              end
            when 'f'.ord
              if s[2] == 'o'.ord
                add_match(id + 25 * n, l + 5, l, matches) if s[3] == 'r'.ord && s[4] == ' '.ord
              elsif s[2] == 'r'.ord
                add_match(id + 37 * n, l + 6, l, matches) if s[3] == 'o'.ord && s[4] == 'm'.ord && s[5] == ' '.ord
              end
            when 'o'.ord
              if s[2] == 'f'.ord
                add_match(id + 8 * n, l + 4, l, matches) if s[3] == ' '.ord
              elsif s[2] == 'n'.ord
                add_match(id + 45 * n, l + 4, l, matches) if s[3] == ' '.ord
              end
            when 'n'.ord
              add_match(id + 80 * n, l + 5, l, matches) if s[2] == 'o'.ord && s[3] == 't'.ord && s[4] == ' '.ord
            when 't'.ord
              if s[2] == 'h'.ord
                if s[3] == 'e'.ord
                  add_match(id + 5 * n, l + 5, l, matches) if s[4] == ' '.ord
                elsif s[3] == 'a'.ord
                  add_match(id + 29 * n, l + 6, l, matches) if s[4] == 't'.ord && s[5] == ' '.ord
                end
              elsif s[2] == 'o'.ord
                add_match(id + 17 * n, l + 4, l, matches) if s[3] == ' '.ord
              end
            when 'w'.ord
              add_match(id + 35 * n, l + 6, l, matches) if s[2] == 'i'.ord && s[3] == 't'.ord && s[4] == 'h'.ord && s[5] == ' '.ord
            end
          when '"'.ord
            add_match(id + 19 * n, l + 1, l, matches)
            add_match(id + 21 * n, l + 2, l, matches) if s[1] == '>'.ord
          when '.'.ord
            add_match(id + 20 * n, l + 1, l, matches)
            if s[1] == ' '.ord
              add_match(id + 31 * n, l + 2, l, matches)
              if s[2] == 'T'.ord && s[3] == 'h'.ord
                if s[4] == 'e'.ord
                  add_match(id + 43 * n, l + 6, l, matches) if s[5] == ' '.ord
                elsif s[4] == 'i'.ord
                  add_match(id + 75 * n, l + 7, l, matches) if s[5] == 's'.ord && s[6] == ' '.ord
                end
              end
            end
          when ','.ord
            add_match(id + 76 * n, l + 1, l, matches)
            add_match(id + 14 * n, l + 2, l, matches) if s[1] == ' '.ord
          when '\n'.ord
            add_match(id + 22 * n, l + 1, l, matches)
            add_match(id + 50 * n, l + 2, l, matches) if s[1] == '\t'.ord
          when ']'.ord
            add_match(id + 24 * n, l + 1, l, matches)
          when '\''.ord
            add_match(id + 36 * n, l + 1, l, matches)
          when ':'.ord
            add_match(id + 51 * n, l + 1, l, matches)
          when '('.ord
            add_match(id + 57 * n, l + 1, l, matches)
          when '='.ord
            if s[1] == '"'.ord
              add_match(id + 70 * n, l + 2, l, matches)
            elsif s[1] == '\''.ord
              add_match(id + 86 * n, l + 2, l, matches)
            end
          when 'a'.ord
            add_match(id + 84 * n, l + 3, l, matches) if s[1] == 'l'.ord && s[2] == ' '.ord
          when 'e'.ord
            if s[1] == 'd'.ord
              add_match(id + 53 * n, l + 3, l, matches) if s[2] == ' '.ord
            elsif s[1] == 'r'.ord
              add_match(id + 82 * n, l + 3, l, matches) if s[2] == ' '.ord
            elsif s[1] == 's'.ord
              add_match(id + 95 * n, l + 4, l, matches) if s[2] == 't'.ord && s[3] == ' '.ord
            end
          when 'f'.ord
            add_match(id + 90 * n, l + 4, l, matches) if s[1] == 'u'.ord && s[2] == 'l'.ord && s[3] == ' '.ord
          when 'i'.ord
            if s[1] == 'v'.ord
              add_match(id + 92 * n, l + 4, l, matches) if s[2] == 'e'.ord && s[3] == ' '.ord
            elsif s[1] == 'z'.ord
              add_match(id + 100 * n, l + 4, l, matches) if s[2] == 'e'.ord && s[3] == ' '.ord
            end
          when 'l'.ord
            if s[1] == 'e'.ord
              add_match(id + 93 * n, l + 5, l, matches) if s[2] == 's'.ord && s[3] == 's'.ord && s[4] == ' '.ord
            elsif s[1] == 'y'.ord
              add_match(id + 61 * n, l + 3, l, matches) if s[2] == ' '.ord
            end
          when 'o'.ord
            add_match(id + 106 * n, l + 4, l, matches) if s[1] == 'u'.ord && s[2] == 's'.ord && s[3] == ' '.ord
          end
        else
          all_caps = w.transform != UPPERCASE_FIRST
          next unless matches?(l, w.transform, id, data, max_length)
          add_match(id + (all_caps ? 44 : 9) * n, l, l, matches)
          found = true
          next if l + 1 >= max_length
          s = data + l
          case s[0]
          when ' '.ord
            add_match(id + (all_caps ? 68 : 4) * n, l + 1, l, matches)
          when '"'.ord
            add_match(id + (all_caps ? 87 : 66) * n, l + 1, l, matches)
            add_match(id + (all_caps ? 97 : 69) * n, l + 2, l, matches) if s[1] == '>'.ord
          when '.'.ord
            add_match(id + (all_caps ? 101 : 79) * n, l + 1, l, matches)
            add_match(id + (all_caps ? 114 : 88) * n, l + 2, l, matches) if s[1] == ' '.ord
          when ','.ord
            add_match(id + (all_caps ? 112 : 99) * n, l + 1, l, matches)
            add_match(id + (all_caps ? 107 : 58) * n, l + 2, l, matches) if s[1] == ' '.ord
          when '\''.ord
            add_match(id + (all_caps ? 94 : 74) * n, l + 1, l, matches)
          when '('.ord
            add_match(id + (all_caps ? 113 : 78) * n, l + 1, l, matches)
          when '='.ord
            if s[1] == '"'.ord
              add_match(id + (all_caps ? 105 : 104) * n, l + 2, l, matches)
            elsif s[1] == '\''.ord
              add_match(id + (all_caps ? 116 : 108) * n, l + 2, l, matches)
            end
          end
        end
      end
      if max_length >= 5 && (data[0] == ' '.ord || data[0] == '.'.ord)
        space = data[0] == ' '.ord
        offset = buckets[Encode.hash15(data + 1)].to_i32
        done = offset == 0
        until done
          w = words[offset]
          offset += 1
          l = (w.length & 0x1F).to_i32
          n = 1 << Dictionary::SIZE_BITS_BY_LENGTH[l]
          id = w.index.to_i32
          done = w.length & 0x80 != 0
          if w.transform == IDENTITY
            next unless matches?(l, w.transform, id, data + 1, max_length - 1)
            add_match(id + (space ? 6 : 32) * n, l + 1, l, matches)
            found = true
            next if l + 2 >= max_length
            s = data + l + 1
            if s[0] == ' '.ord
              add_match(id + (space ? 2 : 77) * n, l + 2, l, matches)
            elsif s[0] == '('.ord
              add_match(id + (space ? 89 : 67) * n, l + 2, l, matches)
            elsif space
              if s[0] == ','.ord
                add_match(id + 103 * n, l + 2, l, matches)
                add_match(id + 33 * n, l + 3, l, matches) if s[1] == ' '.ord
              elsif s[0] == '.'.ord
                add_match(id + 71 * n, l + 2, l, matches)
                add_match(id + 52 * n, l + 3, l, matches) if s[1] == ' '.ord
              elsif s[0] == '='.ord
                if s[1] == '"'.ord
                  add_match(id + 81 * n, l + 3, l, matches)
                elsif s[1] == '\''.ord
                  add_match(id + 98 * n, l + 3, l, matches)
                end
              end
            end
          elsif space
            all_caps = w.transform != UPPERCASE_FIRST
            next unless matches?(l, w.transform, id, data + 1, max_length - 1)
            add_match(id + (all_caps ? 85 : 30) * n, l + 1, l, matches)
            found = true
            next if l + 2 >= max_length
            s = data + l + 1
            if s[0] == ' '.ord
              add_match(id + (all_caps ? 83 : 15) * n, l + 2, l, matches)
            elsif s[0] == ','.ord
              add_match(id + 109 * n, l + 2, l, matches) unless all_caps
              add_match(id + (all_caps ? 111 : 65) * n, l + 3, l, matches) if s[1] == ' '.ord
            elsif s[0] == '.'.ord
              add_match(id + (all_caps ? 115 : 96) * n, l + 2, l, matches)
              add_match(id + (all_caps ? 117 : 91) * n, l + 3, l, matches) if s[1] == ' '.ord
            elsif s[0] == '='.ord
              if s[1] == '"'.ord
                add_match(id + (all_caps ? 110 : 118) * n, l + 3, l, matches)
              elsif s[1] == '\''.ord
                add_match(id + (all_caps ? 119 : 120) * n, l + 3, l, matches)
              end
            end
          end
        end
      end
      if max_length >= 6
        if (data[1] == ' '.ord && (data[0] == 'e'.ord || data[0] == 's'.ord || data[0] == ','.ord)) ||
           (data[0] == 0xC2 && data[1] == 0xA0)
          offset = buckets[Encode.hash15(data + 2)].to_i32
          done = offset == 0
          until done
            w = words[offset]
            offset += 1
            l = (w.length & 0x1F).to_i32
            n = 1 << Dictionary::SIZE_BITS_BY_LENGTH[l]
            id = w.index.to_i32
            done = w.length & 0x80 != 0
            if w.transform == IDENTITY && matches?(l, w.transform, id, data + 2, max_length - 2)
              if data[0] == 0xC2
                add_match(id + 102 * n, l + 2, l, matches)
                found = true
              elsif l + 2 < max_length && data[l + 2] == ' '.ord
                t = data[0] == 'e'.ord ? 18 : (data[0] == 's'.ord ? 7 : 13)
                add_match(id + t * n, l + 3, l, matches)
                found = true
              end
            end
          end
        end
      end
      if max_length >= 9
        if (data[0] == ' '.ord && data[1] == 't'.ord && data[2] == 'h'.ord && data[3] == 'e'.ord && data[4] == ' '.ord) ||
           (data[0] == '.'.ord && data[1] == 'c'.ord && data[2] == 'o'.ord && data[3] == 'm'.ord && data[4] == '/'.ord)
          offset = buckets[Encode.hash15(data + 5)].to_i32
          done = offset == 0
          until done
            w = words[offset]
            offset += 1
            l = (w.length & 0x1F).to_i32
            n = 1 << Dictionary::SIZE_BITS_BY_LENGTH[l]
            id = w.index.to_i32
            done = w.length & 0x80 != 0
            if w.transform == IDENTITY && matches?(l, w.transform, id, data + 5, max_length - 5)
              add_match(id + (data[0] == ' '.ord ? 41 : 72) * n, l + 5, l, matches)
              found = true
              if l + 5 < max_length
                s = data + l + 5
                if data[0] == ' '.ord
                  if l + 8 < max_length && s[0] == ' '.ord && s[1] == 'o'.ord && s[2] == 'f'.ord && s[3] == ' '.ord
                    add_match(id + 62 * n, l + 9, l, matches)
                    if l + 12 < max_length && s[4] == 't'.ord && s[5] == 'h'.ord && s[6] == 'e'.ord && s[7] == ' '.ord
                      add_match(id + 73 * n, l + 13, l, matches)
                    end
                  end
                end
              end
            end
          end
        end
      end
      found
    end
  end
end
