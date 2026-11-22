module Amber::Mica::Core
  # Substring search in linear time, for query engines that run caller- or
  # attacker-supplied patterns (stdlib `String#index(String)` is a
  # Rabin-Karp search with a fixed base, so crafted inputs can make it
  # quadratic).
  #
  # The search is Knuth-Morris-Pratt over bytes: at most
  # `2 * haystack.size + 2 * needle.size` comparisons, plus `needle.size`
  # steps for allocating the failure table, all reported to the step block
  # before they happen. UTF-8 is
  # self-synchronizing, so a byte match of a valid UTF-8 needle in valid
  # UTF-8 text always starts on a character boundary.
  module ByteSearch
    # Comparisons between two calls of the step block.
    STEP_CHUNK = 4096

    # Returns the byte offset of the first occurrence of *needle* in
    # *haystack*, or nil. The block is called with the number of
    # comparisons about to be made, in blocks of at most `STEP_CHUNK`
    # (while building the failure table and while scanning), before they
    # run, so a work meter can stop a long search before its work.
    #
    # ```
    # Amber::Mica::Core::ByteSearch.index("aaab".to_slice, "ab".to_slice) # => 2
    # ```
    def self.index(haystack : Bytes, needle : Bytes, & : Int32 ->) : Int32?
      return 0 if needle.empty?
      return if needle.size > haystack.size
      failure = failure_table(needle) { |steps| yield steps }
      matched = 0
      # Comparisons are reported in blocks before they run: *prepaid* is
      # what the last report still covers, *bound* what the scan can still
      # need (at most 2 * haystack.size comparisons).
      prepaid = 0
      bound = 2_i64 * haystack.size
      offset = 0
      while offset < haystack.size
        # One comparison per iteration, each reported before it runs (and
        # before the haystack byte is read).
        loop do
          if prepaid == 0
            prepaid, bound = prepay(bound) { |steps| yield steps }
          end
          prepaid -= 1
          if needle[matched] == haystack[offset]
            matched += 1
            break
          end
          break if matched == 0
          matched = failure[matched - 1]
        end
        return offset + 1 - needle.size if matched == needle.size
        offset += 1
      end
      nil
    end

    # Reports the next block of at most `STEP_CHUNK` steps (at least one)
    # out of *bound*, before they run. Returns the block and what remains.
    private def self.prepay(bound : Int64, & : Int32 ->) : {Int32, Int64}
      chunk = Math.max(Math.min(bound, STEP_CHUNK.to_i64), 1_i64).to_i32
      yield chunk
      {chunk, Math.max(bound - chunk, 0_i64)}
    end

    # :ditto:
    def self.index(haystack : Bytes, needle : Bytes) : Int32?
      index(haystack, needle) { }
    end

    # Returns the KMP failure function: entry *i* is the length of the
    # longest proper prefix of `needle[0..i]` that is also its suffix. Each
    # loop iteration either advances or shrinks `length`, so the loop runs
    # at most `2 * needle.size` times; the block gets the count in chunks.
    private def self.failure_table(needle : Bytes, & : Int32 ->) : Array(Int32)
      # The table's allocation and zero fill are linear in the needle, so
      # they are counted, in chunks, before they happen.
      remaining = needle.size
      while remaining > 0
        chunk = Math.min(remaining, STEP_CHUNK)
        yield chunk
        remaining -= chunk
      end
      table = Array(Int32).new(needle.size, 0)
      length = 0
      index = 1
      prepaid = 0
      bound = 2_i64 * needle.size
      while index < needle.size
        if prepaid == 0
          prepaid, bound = prepay(bound) { |steps| yield steps }
        end
        prepaid -= 1
        if needle[index] == needle[length]
          length += 1
          table[index] = length
          index += 1
        elsif length > 0
          length = table[length - 1]
        else
          table[index] = 0
          index += 1
        end
      end
      table
    end
  end
end
