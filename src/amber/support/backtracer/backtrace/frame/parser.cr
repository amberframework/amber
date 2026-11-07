module Backtracer
  module Backtrace::Frame::Parser
    extend self

    # The parts of one backtrace line.
    private record LineParts, method : String?, file : String? = nil, lineno : Int32? = nil, column : Int32? = nil

    # Parses a single line of a given backtrace, where *line* is
    # the raw line from `caller` or some backtrace.
    #
    # Accepts options:
    # - `configuration`: `Configuration` object - uses `Backtracer.configuration` if `nil`
    #
    # Returns parsed `Backtrace::Frame` on success or `nil` otherwise.
    def parse?(line : String, **options) : Backtrace::Frame?
      return nil if line.empty? || line.includes?('\n')

      parts = crystal_method_parts(line) || crystal_proc_parts(line) || crystal_crash_parts(line) || LineParts.new(line)
      method = parts.method.presence
      return unless method

      Backtrace::Frame.new method, parts.file.presence, parts.lineno, parts.column,
        configuration: options[:configuration]?
    end

    # Same as `parse?` but raises `ArgumentError` on error.
    def parse(line : String, **options) : Backtrace::Frame
      parse?(line, **options) ||
        raise ArgumentError.new("Error parsing line: #{line.inspect}")
    end

    # `lib/foo/src/foo/bar.cr:50:7 in '*Foo::Bar#_baz:Foo::Bam' at 0x10`
    private def crystal_method_parts(line : String) : LineParts?
      marker_index = line.rindex(" in '")
      return nil unless marker_index

      location = line[0, marker_index]
      rest = without_trailing_address(line[(marker_index + 5)..])
      return nil unless rest.ends_with?('\'')

      file, _, position = location.partition(':')
      return nil if file.empty?

      line_text, _, column_text = position.partition(':')
      return nil unless position.empty? || (digits?(line_text) && (column_text.empty? ? !position.ends_with?(':') : digits?(column_text)))

      LineParts.new(rest.rchop('\'').lchop('*'), file, line_text.to_i?, column_text.to_i?)
    end

    # `~procProc(Nil)@/usr/local/src/http/server.cr:148 at 0x102cee376`
    private def crystal_proc_parts(line : String) : LineParts?
      return nil unless line.starts_with?('~')

      method, separator, location = line.partition('@')
      return nil if separator.empty? || method.size < 2

      file, _, line_text = without_trailing_address(location).partition(':')
      return nil if file.empty? || !digits?(line_text)

      LineParts.new(method, file, line_text.to_i?)
    end

    # `[0x1057a9fab] *CallStack::print_backtrace:Int32 +107 (2 times)`
    private def crystal_crash_parts(line : String) : LineParts?
      return nil unless line.starts_with?("[0x") || line.starts_with?("[0X")

      closing_bracket_index = line.index("] ")
      return nil unless closing_bracket_index && hex_digits?(line[3...closing_bracket_index])

      rest = line[(closing_bracket_index + 2)..]
      if rest.ends_with?(" times)")
        times_index = rest.rindex(" (")
        return nil unless times_index && digits?(rest[(times_index + 2)...-7])

        rest = rest[0, times_index]
      end

      offset_index = rest.rindex(" +")
      return nil unless offset_index && digits?(rest[(offset_index + 2)..])

      LineParts.new(rest[0, offset_index].lchop('*'))
    end

    private def without_trailing_address(text : String) : String
      address_index = text.rindex(" at 0")
      return text unless address_index

      address = text[(address_index + 4)..]
      return text unless address.starts_with?("0x") || address.starts_with?("0X")

      hex_digits?(address[2..]) ? text[0, address_index] : text
    end

    private def digits?(text : String) : Bool
      !text.empty? && text.each_char.all?(&.ascii_number?)
    end

    private def hex_digits?(text : String) : Bool
      !text.empty? && text.each_char.all?(&.hex?)
    end
  end
end
