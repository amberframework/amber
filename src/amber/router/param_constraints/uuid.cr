require "../param_constraint"

module Amber::Router::ParamConstraints
  # Matches a UUID in its 36-character hyphenated form, such as
  # `550e8400-e29b-41d4-a716-446655440000`, in either letter case.
  struct Uuid
    include Amber::Router::ParamConstraint

    TEXT_LENGTH = 36

    def matches?(segment : String) : Bool
      matches_bytes?(segment.to_slice)
    end

    def matches_span?(path : String, byte_offset : Int32, bytesize : Int32) : Bool
      matches_bytes?(path.to_slice[byte_offset, bytesize])
    end

    private def matches_bytes?(bytes : Bytes) : Bool
      return false unless bytes.size == TEXT_LENGTH
      bytes.each_with_index do |byte, index|
        if index.in?(8, 13, 18, 23)
          return false unless byte === '-'
        else
          return false unless byte.unsafe_chr.hex?
        end
      end
      true
    end

    def to_s(io : IO) : Nil
      io << "uuid"
    end
  end
end
