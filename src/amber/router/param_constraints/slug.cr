require "../param_constraint"

module Amber::Router::ParamConstraints
  # Matches a lowercase slug: runs of `a-z` and `0-9` joined by single
  # hyphens, such as `my-post-123`. A slug never starts or ends with a hyphen
  # and never has two in a row.
  struct Slug
    include Amber::Router::ParamConstraint

    def matches?(segment : String) : Bool
      matches_bytes?(segment.to_slice)
    end

    def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
      matches_bytes?(path.to_slice[byte_offset, bytesize])
    end

    private def matches_bytes?(bytes : Bytes) : Bool
      return false if bytes.empty?
      previous_was_hyphen = true # so a leading hyphen fails
      bytes.each do |byte|
        if byte === '-'
          return false if previous_was_hyphen
          previous_was_hyphen = true
        elsif ('a'.ord <= byte <= 'z'.ord) || ('0'.ord <= byte <= '9'.ord)
          previous_was_hyphen = false
        else
          return false
        end
      end
      !previous_was_hyphen
    end

    def to_s(io : IO) : Nil
      io << "slug"
    end
  end
end
