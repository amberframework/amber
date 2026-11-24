module Amber::Mica::Brotli::Encode
  # Per-byte literal cost estimates and the UTF-8 test (google/brotli's
  # literal_cost.c and utf8_util.c).
  module LiteralCost
    MIN_UTF8_RATIO = 0.75

    # Bytes read and whether they were UTF-8 (google/brotli's
    # BrotliParseAsUTF8, as a length and a flag).
    @[AlwaysInline]
    private def self.parse_utf8(input : UInt8*, size : Int32) : {Int32, Bool}
      b0 = input[0].to_i32
      if b0 & 0x80 == 0
        return {1, true} if b0 > 0
      end
      if size > 1 && b0 & 0xE0 == 0xC0 && input[1] & 0xC0 == 0x80
        symbol = ((b0 & 0x1F) << 6) | (input[1] & 0x3F).to_i32
        return {2, true} if symbol > 0x7F
      end
      if size > 2 && b0 & 0xF0 == 0xE0 && input[1] & 0xC0 == 0x80 && input[2] & 0xC0 == 0x80
        symbol = ((b0 & 0x0F) << 12) | ((input[1] & 0x3F).to_i32 << 6) | (input[2] & 0x3F).to_i32
        return {3, true} if symbol > 0x7FF
      end
      if size > 3 && b0 & 0xF8 == 0xF0 && input[1] & 0xC0 == 0x80 && input[2] & 0xC0 == 0x80 && input[3] & 0xC0 == 0x80
        symbol = ((b0 & 0x07) << 18) | ((input[1] & 0x3F).to_i32 << 12) | ((input[2] & 0x3F).to_i32 << 6) | (input[3] & 0x3F).to_i32
        return {4, true} if symbol > 0xFFFF && symbol <= 0x10FFFF
      end
      {1, false}
    end

    # Whether at least 75% of `data[0, length]` is UTF-8.
    def self.mostly_utf8?(data : UInt8*, length : Int32) : Bool
      size_utf8 = 0
      i = 0
      while i < length
        read, utf8 = parse_utf8(data + i, length - i)
        size_utf8 += read if utf8
        i += read
      end
      size_utf8.to_f64 > MIN_UTF8_RATIO * length
    end

    @[AlwaysInline]
    private def self.utf8_position(last : Int32, c : Int32, clamp : Int32) : Int32
      if c < 128
        0
      elsif c >= 192
        Math.min(1, clamp)
      elsif last < 0xE0
        0
      else
        Math.min(2, clamp)
      end
    end

    private def self.multi_byte_stats_level(data : UInt8*, length : Int32) : Int32
      counts = StaticArray(Int32, 3).new(0)
      max_utf8 = 1
      last = 0
      length.times do |i|
        c = data[i].to_i32
        counts[utf8_position(last, c, 2)] += 1
        last = c
      end
      max_utf8 = 1 if counts[2] < 500
      max_utf8 = 0 if counts[1] + counts[2] < 25
      max_utf8
    end

    # Estimated bits of each literal of `data[0, length]` into `cost`
    # (google/brotli's BrotliEstimateBitCostsForLiterals).
    def self.estimate(data : UInt8*, length : Int32, cost : Float32*) : Nil
      if mostly_utf8?(data, length)
        estimate_utf8(data, length, cost)
        return
      end
      histogram = StaticArray(Int32, 256).new(0)
      window_half = 2000
      in_window = Math.min(window_half, length)
      in_window.times { |i| histogram[data[i]] += 1 }
      length.times do |i|
        if i >= window_half
          histogram[data[i - window_half]] -= 1
          in_window -= 1
        end
        if i + window_half < length
          histogram[data[i + window_half]] += 1
          in_window += 1
        end
        histo = histogram[data[i]]
        histo = 1 if histo == 0
        lit_cost = Encode.fast_log2(in_window) - Encode.fast_log2(histo) + 0.029
        if lit_cost < 1.0
          lit_cost *= 0.5
          lit_cost += 0.5
        end
        cost[i] = lit_cost.to_f32
      end
    end

    private def self.estimate_utf8(data : UInt8*, length : Int32, cost : Float32*) : Nil
      max_utf8 = multi_byte_stats_level(data, length)
      window_half = 495
      in_window = Math.min(window_half, length)
      in_window_utf8 = StaticArray(Int32, 3).new(0)
      histogram = StaticArray(Int32, 768).new(0)
      last = 0
      utf8_pos = 0
      in_window.times do |i|
        c = data[i].to_i32
        histogram[256 * utf8_pos + c] += 1
        in_window_utf8[utf8_pos] += 1
        utf8_pos = utf8_position(last, c, max_utf8)
        last = c
      end
      length.times do |i|
        if i >= window_half
          c = i < window_half + 1 ? 0 : data[i - window_half - 1].to_i32
          last_c = i < window_half + 2 ? 0 : data[i - window_half - 2].to_i32
          pos2 = utf8_position(last_c, c, max_utf8)
          histogram[256 * pos2 + data[i - window_half]] -= 1
          in_window_utf8[pos2] -= 1
        end
        if i + window_half < length
          c = data[i + window_half - 1].to_i32
          last_c = data[i + window_half - 2].to_i32
          pos2 = utf8_position(last_c, c, max_utf8)
          histogram[256 * pos2 + data[i + window_half]] += 1
          in_window_utf8[pos2] += 1
        end
        c = i < 1 ? 0 : data[i - 1].to_i32
        last_c = i < 2 ? 0 : data[i - 2].to_i32
        position = utf8_position(last_c, c, max_utf8)
        histo = histogram[256 * position + data[i]]
        histo = 1 if histo == 0
        lit_cost = Encode.fast_log2(in_window_utf8[position]) - Encode.fast_log2(histo) + 0.02905
        if lit_cost < 1.0
          lit_cost *= 0.5
          lit_cost += 0.5
        end
        lit_cost += 0.35 + (0.35 / 2000) * i if i < 2000
        cost[i] = lit_cost.to_f32
      end
    end
  end
end
