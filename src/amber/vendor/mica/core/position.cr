module Amber::Mica::Core
  # A place in a format's input, carried by every `Amber::Mica::ParseError`.
  #
  # *byte_offset* is 0-based and counts bytes of the original input, before
  # any transcoding (a byte order mark included). *line* and *column* are
  # 1-based for text formats (the column counts characters) and 0 for formats
  # without lines.
  #
  # ```
  # Amber::Mica::Core::Position.new(42_i64, 3, 7).to_s # => "line 3, column 7, byte 42"
  # Amber::Mica::Core::Position.new(42_i64).to_s       # => "byte 42"
  # ```
  record Position, byte_offset : Int64, line : Int32 = 0, column : Int32 = 0 do
    # Returns true when the position has a line and column.
    def text? : Bool
      @line > 0
    end

    def to_s(io : IO) : Nil
      if text?
        io << "line " << @line << ", column " << @column << ", byte " << @byte_offset
      else
        io << "byte " << @byte_offset
      end
    end
  end
end
