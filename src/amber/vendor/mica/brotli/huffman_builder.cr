module Amber::Mica::Brotli
  # Builds length-limited prefix codes for the encoder: Huffman code
  # lengths no longer than a limit (15 for the RFC 7932 alphabets, 5 for
  # the code length code), and the canonical codes for those lengths with
  # their bits reversed for a least-significant-first bit writer.
  #
  # The limit is met as google/brotli meets it: when the tree is too
  # deep, every count is raised to at least a floor that doubles until
  # the tree fits, which flattens the rare symbols first.
  #
  # :nodoc:
  module HuffmanBuilder
    # Fills `lengths[0, size]` with code lengths for *counts* (0 for an
    # unused symbol) no longer than *limit*. One used symbol gets length 0;
    # two or more get a complete code.
    def self.build_lengths(counts : Slice(UInt32), size : Int32, limit : Int32, lengths : Bytes) : Nil
      lengths[0, size].fill(0_u8)
      used = 0
      size.times { |symbol| used += 1 if counts[symbol] > 0 }
      return if used < 2
      floor = 1_u32
      loop do
        return if try_build(counts, size, limit, lengths, floor, used)
        floor <<= 1
      end
    end

    # Builds the tree with every used count raised to *floor*; false when
    # it is deeper than *limit*.
    private def self.try_build(counts : Slice(UInt32), size : Int32, limit : Int32, lengths : Bytes, floor : UInt32, used : Int32) : Bool
      leaves = Array(Tuple(UInt32, Int32)).new(used)
      size.times do |symbol|
        count = counts[symbol]
        leaves << {Math.max(count, floor), symbol} if count > 0
      end
      leaves.sort!
      # Nodes 0...used are leaves in weight order; internal nodes follow.
      total = 2 * used - 1
      weight = Array(UInt64).new(total, 0_u64)
      parent = Array(Int32).new(total, -1)
      used.times { |index| weight[index] = leaves[index][0].to_u64 }
      leaf = 0
      inner = used
      (used...total).each do |node|
        2.times do
          pick =
            if leaf < used && (inner >= node || weight[leaf] <= weight[inner])
              leaf += 1
              leaf - 1
            else
              inner += 1
              inner - 1
            end
          weight[node] += weight[pick]
          parent[pick] = node
        end
      end
      depth = Array(Int32).new(total, 0)
      (total - 2).downto(0) do |node|
        depth[node] = depth[parent[node]] + 1
        return false if node < used && depth[node] > limit
      end
      used.times { |index| lengths[leaves[index][1]] = depth[index].to_u8 }
      true
    end

    # Fills `codes[0, size]` with the canonical code of each symbol, bits
    # reversed (RFC 7932, section 3.2).
    def self.assign_codes(lengths : Bytes, size : Int32, codes : Slice(UInt16)) : Nil
      count = StaticArray(Int32, 16).new(0)
      size.times { |symbol| count[lengths[symbol]] += 1 }
      count[0] = 0
      next_code = StaticArray(Int32, 16).new(0)
      code = 0
      (1..15).each do |length|
        code = (code + count[length - 1]) << 1
        next_code[length] = code
      end
      size.times do |symbol|
        length = lengths[symbol].to_i32
        next codes[symbol] = 0_u16 if length == 0
        codes[symbol] = reverse(next_code[length], length)
        next_code[length] += 1
      end
    end

    def self.reverse(value : Int32, width : Int32) : UInt16
      result = 0
      width.times do |bit|
        result = (result << 1) | ((value >> bit) & 1)
      end
      result.to_u16
    end
  end
end
